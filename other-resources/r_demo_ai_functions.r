# Databricks notebook source
# MAGIC %md
# MAGIC # R demo: calling Databricks AI Functions via sparklyr
# MAGIC
# MAGIC `02_ai_functions.sql` called `ai_classify` / `ai_extract` / `ai_summarize` from a SQL notebook
# MAGIC cell. They're plain SQL functions, though — any language with a Spark connector can call them
# MAGIC the same way. This notebook proves that from **R**, using
# MAGIC [`sparklyr`](https://spark.posit.co/) connected to this cluster's existing Spark session via
# MAGIC `spark_connect(method = "databricks")` — no separate auth, no REST client, just SQL through R.
# MAGIC
# MAGIC This workspace doesn't have the `complaints` table loaded, so every query below is a
# MAGIC standalone literal-text example, written to read consistently with the workshop dataset.

# COMMAND ----------

library(sparklyr)

sc <- spark_connect(method = "databricks")

# COMMAND ----------

# MAGIC %md
# MAGIC ## A reusable helper: `run_sql()`
# MAGIC
# MAGIC Runs a SQL string against the connected cluster and returns the result as an R data frame.
# MAGIC `sql_quote()` escapes embedded single quotes before splicing a value into the SQL text —
# MAGIC these example narratives don't contain any, but it's good habit for anything that eventually
# MAGIC takes real user input.

# COMMAND ----------

run_sql <- function(sql) sparklyr::collect(sparklyr::sdf_sql(sc, sql))

sql_quote <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. `ai_classify`

# COMMAND ----------

narrative_1 <- paste(
  "I have contacted my credit card company four times about a duplicate charge on my statement",
  "and each time I am told someone will call me back, but nobody ever does."
)

classify_result <- run_sql(sprintf(
  "SELECT ai_classify(%s, ARRAY('Billing or fee dispute', 'Debt collection practices', 'Fraud or unauthorized transaction', 'Credit reporting error', 'Customer service quality', 'Other')) AS category",
  sql_quote(narrative_1)
))
print(classify_result)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. `ai_extract`

# COMMAND ----------

narrative_2 <- paste(
  "On 03/14/2024 I was charged $89.99 by Northgate Financial Services for a service I never",
  "signed up for, and they still have not refunded me."
)

extract_result <- run_sql(sprintf(
  "SELECT ai_extract(%s, ARRAY('company name mentioned', 'dollar amount mentioned', 'date mentioned')) AS extracted_fields",
  sql_quote(narrative_2)
))
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

summarize_result <- run_sql(sprintf(
  "SELECT ai_summarize(%s, 40) AS narrative_summary",
  sql_quote(narrative_3)
))
print(summarize_result)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Chaining: summarize, then classify the summary
# MAGIC
# MAGIC Same idea as `02_ai_functions.sql`'s chaining cell — reason over the cheaper, shorter summary
# MAGIC instead of the full narrative — but here the chaining happens **across two separate calls**,
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

summary_step <- run_sql(sprintf(
  "SELECT ai_summarize(%s, 40) AS narrative_summary",
  sql_quote(narrative_4)
))
summary_text <- summary_step$narrative_summary[1]
cat("Summary:", summary_text, "\n")

urgency_step <- run_sql(sprintf(
  "SELECT ai_classify(%s, ARRAY('High', 'Medium', 'Low')) AS urgency",
  sql_quote(summary_text)
))
cat("Urgency:", urgency_step$urgency[1], "\n")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Closing note
# MAGIC
# MAGIC `ai_classify` / `ai_extract` / `ai_summarize` are plain SQL functions — `sparklyr` just gives R
# MAGIC a way to send SQL to the same Spark engine this cluster already runs. Nothing above is
# MAGIC R-specific: PySpark, Scala Spark, or a `%sql` cell on this same cluster would call these
# MAGIC functions exactly the same way. R was today's example; the functions don't care what sent them
# MAGIC the query.
