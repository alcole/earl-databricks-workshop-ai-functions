# Databricks notebook source
# MAGIC %md
# MAGIC # R demo: calling Databricks AI Functions via the SQL Statement Execution API
# MAGIC
# MAGIC `02_ai_functions.sql` called `ai_classify` / `ai_extract` / `ai_summarize` from a SQL notebook
# MAGIC cell. That's one client talking to one warehouse — but the warehouse is just compute sitting
# MAGIC behind a REST API. Anything that can make an HTTP call can run the exact same SQL, including
# MAGIC these AI functions, without ever opening the SQL editor.
# MAGIC
# MAGIC This notebook proves that by calling the same functions from **R**, using the
# MAGIC [SQL Statement Execution API](https://docs.databricks.com/aws/en/dev-tools/sql-execution-tutorial)
# MAGIC directly: POST a statement, poll until it finishes, get rows back. R isn't special here — the
# MAGIC point is the API, not the language (see the closing note at the bottom).
# MAGIC
# MAGIC This workspace doesn't have the `complaints` table loaded, so every query below is a
# MAGIC standalone literal-text example, written to read consistently with the workshop dataset.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Auth: get a short-lived token, don't hardcode one
# MAGIC
# MAGIC A couple of ways to get a token into this notebook without committing one to the repo:
# MAGIC
# MAGIC - **What this notebook uses**: widgets, populated at run time. Run
# MAGIC   `databricks auth token -p dra-dev` in your terminal, copy the `access_token` value (it's an
# MAGIC   OAuth token, valid for about an hour), and paste it into the `token` widget below. Widget
# MAGIC   *values* aren't part of the notebook's saved source — only the (empty) default is — so
# MAGIC   nothing sensitive ends up in git.
# MAGIC - **Why not `dbutils.notebook.getContext()$apiToken`?** This in-notebook trick shows up in a lot
# MAGIC   of community examples, but it isn't officially documented, and is known to fail on newer
# MAGIC   Shared Access Mode clusters — not something to rely on right before a live demo.
# MAGIC - **Alternative for a fully hands-off run**: set `DATABRICKS_TOKEN` as a cluster environment
# MAGIC   variable (Cluster → Advanced Options → Spark → Environment Variables) instead of a widget,
# MAGIC   and swap the `dbutils.widgets.get("token")` call below for `Sys.getenv("DATABRICKS_TOKEN")`.

# COMMAND ----------

dbutils.widgets.text("host", "https://adb-1405986770269510.10.azuredatabricks.net", "Databricks host")
dbutils.widgets.text("warehouse_id", "b0600754dcddc59e", "SQL warehouse ID (dev-dra-sqlwh)")
dbutils.widgets.text("token", "", "Token (paste output of: databricks auth token -p dra-dev)")

# COMMAND ----------

if (!requireNamespace("httr", quietly = TRUE)) install.packages("httr")
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")
library(httr)
library(jsonlite)

HOST <- dbutils.widgets.get("host")
WAREHOUSE_ID <- dbutils.widgets.get("warehouse_id")
TOKEN <- dbutils.widgets.get("token")

stopifnot("Paste a token into the 'token' widget first (see the auth cell above)." = nzchar(TOKEN))

# COMMAND ----------

# MAGIC %md
# MAGIC ## A reusable helper: `run_databricks_sql()`
# MAGIC
# MAGIC POSTs a statement to `/api/2.0/sql/statements`, polls `GET .../{statement_id}` until the state
# MAGIC is no longer pending, and returns the result as a data frame. Uses the API's `parameters`
# MAGIC field (`:name` markers in the SQL, bound via a `name`/`value`/`type` list) instead of pasting
# MAGIC values into the SQL string directly — this is Databricks' own recommended way to avoid SQL
# MAGIC injection when a query is built dynamically, which is exactly what's happening here.

# COMMAND ----------

`%||%` <- function(a, b) if (!is.null(a)) a else b

run_databricks_sql <- function(statement, warehouse_id = WAREHOUSE_ID, host = HOST, token = TOKEN,
                                parameters = NULL, poll_interval_secs = 2, timeout_secs = 120) {
  body <- list(warehouse_id = warehouse_id, statement = statement, wait_timeout = "0s")
  if (!is.null(parameters)) body$parameters <- parameters

  post_resp <- httr::POST(
    url = paste0(host, "/api/2.0/sql/statements"),
    httr::add_headers(Authorization = paste("Bearer", token)),
    httr::content_type_json(),
    body = jsonlite::toJSON(body, auto_unbox = TRUE)
  )
  httr::stop_for_status(post_resp, task = "submit SQL statement")
  parsed <- httr::content(post_resp, as = "parsed", simplifyVector = FALSE)
  statement_id <- parsed$statement_id

  start_time <- Sys.time()
  while (parsed$status$state %in% c("PENDING", "RUNNING")) {
    if (as.numeric(Sys.time() - start_time, units = "secs") > timeout_secs) {
      stop(sprintf("Statement %s did not finish within %ds", statement_id, timeout_secs))
    }
    Sys.sleep(poll_interval_secs)
    get_resp <- httr::GET(
      url = paste0(host, "/api/2.0/sql/statements/", statement_id),
      httr::add_headers(Authorization = paste("Bearer", token))
    )
    httr::stop_for_status(get_resp, task = "poll SQL statement")
    parsed <- httr::content(get_resp, as = "parsed", simplifyVector = FALSE)
  }

  state <- parsed$status$state
  if (state != "SUCCEEDED") {
    err <- parsed$status$error$message %||% "(no error message returned)"
    stop(sprintf("Statement %s: %s", state, err))
  }

  cols <- vapply(parsed$manifest$schema$columns, function(c) c$name, character(1))
  rows <- parsed$result$data_array
  if (is.null(rows) || length(rows) == 0) {
    return(as.data.frame(matrix(nrow = 0, ncol = length(cols), dimnames = list(NULL, cols))))
  }
  df <- as.data.frame(do.call(rbind, lapply(rows, function(r) as.data.frame(t(r), stringsAsFactors = FALSE))))
  colnames(df) <- cols
  df
}

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. `ai_classify`

# COMMAND ----------

narrative_1 <- paste(
  "I have contacted my credit card company four times about a duplicate charge on my statement",
  "and each time I am told someone will call me back, but nobody ever does."
)

classify_result <- run_databricks_sql(
  "SELECT ai_classify(:narrative, ARRAY('Billing or fee dispute', 'Debt collection practices', 'Fraud or unauthorized transaction', 'Credit reporting error', 'Customer service quality', 'Other')) AS category",
  parameters = list(list(name = "narrative", value = narrative_1, type = "STRING"))
)
print(classify_result)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. `ai_extract`

# COMMAND ----------

narrative_2 <- paste(
  "On 03/14/2024 I was charged $89.99 by Northgate Financial Services for a service I never",
  "signed up for, and they still have not refunded me."
)

extract_result <- run_databricks_sql(
  "SELECT ai_extract(:narrative, ARRAY('company name mentioned', 'dollar amount mentioned', 'date mentioned')) AS extracted_fields",
  parameters = list(list(name = "narrative", value = narrative_2, type = "STRING"))
)
print(extract_result)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. `ai_summarize`

# COMMAND ----------

narrative_3 <- paste(
  "I applied for a personal loan through Meridian Lending in January and was approved, but the",
  "funds were never deposited into my account. I have called six times over the past two months",
  "and each representative gives me a different explanation. Nobody has been able to tell me",
  "when, or if, the loan will actually be funded."
)

summarize_result <- run_databricks_sql(
  "SELECT ai_summarize(:narrative, 40) AS narrative_summary",
  parameters = list(list(name = "narrative", value = narrative_3, type = "STRING"))
)
print(summarize_result)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Chaining: summarize, then classify the summary
# MAGIC
# MAGIC Same idea as `02_ai_functions.sql`'s chaining cell — reason over the cheaper, shorter summary
# MAGIC instead of the full narrative — but here the chaining happens **across two separate API calls**,
# MAGIC with the intermediate result crossing back into R in between. That's a second way to chain AI
# MAGIC functions beyond a SQL CTE: the client can hold, inspect, or branch on an intermediate result
# MAGIC before deciding what the next call should even be.

# COMMAND ----------

narrative_4 <- paste(
  "A debt collector representing a company I have never heard of has called me at work three times",
  "this week demanding immediate payment of $2,400 and threatening legal action if I do not pay by",
  "tomorrow. I do not recognize this debt and have asked repeatedly for written verification, which",
  "they have refused to provide."
)

summary_step <- run_databricks_sql(
  "SELECT ai_summarize(:narrative, 40) AS narrative_summary",
  parameters = list(list(name = "narrative", value = narrative_4, type = "STRING"))
)
summary_text <- summary_step$narrative_summary[1]
cat("Summary:", summary_text, "\n")

urgency_step <- run_databricks_sql(
  "SELECT ai_classify(:summary, ARRAY('High', 'Medium', 'Low')) AS urgency",
  parameters = list(list(name = "summary", value = summary_text, type = "STRING"))
)
cat("Urgency:", urgency_step$urgency[1], "\n")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Closing note
# MAGIC
# MAGIC Nothing above is R-specific — it's an HTTP POST, a poll loop, and JSON parsing. The same
# MAGIC pattern works from Python (`requests`), Java (`HttpClient`), or literally any language with an
# MAGIC HTTP client and a bearer token. R was today's example; the warehouse and the AI functions
# MAGIC behind it don't care what called them.
