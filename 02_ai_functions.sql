-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 2. SQL AI Functions — hands-on companion
-- MAGIC
-- MAGIC Databricks ships a set of built-in SQL functions that call a foundation model directly from
-- MAGIC a query — no endpoint to stand up, no client library, just SQL. This notebook is the
-- MAGIC hands-on companion to the slides; it exercises three of them against the `complaints` table
-- MAGIC from **01_ingest_data.sql**:
-- MAGIC
-- MAGIC - **`ai_classify(text, labels)`** — sorts free text into one of a fixed list of labels you provide.
-- MAGIC   Good for routing, tagging, and turning unstructured text into a groupable column.
-- MAGIC - **`ai_extract(text, fields)`** — pulls named fields out of free text and returns them as a
-- MAGIC   struct, without you writing a regex or a parser for every field.
-- MAGIC - **`ai_summarize(text, [max_words])`** — condenses free text down to a short summary, optionally
-- MAGIC   bounded to a target length.
-- MAGIC
-- MAGIC Every example below runs against a small `LIMIT`-ed sample, not the full table — that keeps
-- MAGIC things fast and cheap for a live room. Feel free to raise the limits later on your own time.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema
-- MAGIC Match whatever you used in `01_ingest_data.sql`.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';
CREATE WIDGET TEXT schema DEFAULT 'workshop';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2.1 `ai_classify` — sort each complaint into a category
-- MAGIC
-- MAGIC The categories below aren't generic — they were picked by skimming the actual narratives in
-- MAGIC this sample: a lot of debt-collector harassment, credit-reporting disputes, mortgage/loan
-- MAGIC servicing complaints, and disputed charges. `ai_classify` picks the single best-fitting label
-- MAGIC per row.

-- COMMAND ----------

SELECT
  complaint_id,
  product,
  ai_classify(
    narrative,
    ARRAY(
      'Billing or fee dispute',
      'Debt collection practices',
      'Fraud or unauthorized transaction',
      'Credit reporting error',
      'Customer service quality',
      'Other'
    )
  ) AS category
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
LIMIT 15;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2.2 `ai_extract` — pull structured fields out of free text
-- MAGIC
-- MAGIC Narratives frequently mention a company, a dollar amount, and a date — but never in a
-- MAGIC consistent format. `ai_extract` returns a struct with one key per field you ask for; any field
-- MAGIC not present in the text comes back `null` rather than causing an error.

-- COMMAND ----------

SELECT
  complaint_id,
  ai_extract(
    narrative,
    ARRAY('company name mentioned', 'dollar amount mentioned', 'date mentioned')
  ) AS extracted_fields
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
LIMIT 15;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2.3 `ai_summarize` — condense a narrative to one line
-- MAGIC
-- MAGIC The optional second argument caps the summary length in words — useful when the summary
-- MAGIC itself needs to fit in a table column or feed into a downstream step (more on that below).

-- COMMAND ----------

SELECT
  complaint_id,
  product,
  ai_summarize(narrative, 40) AS narrative_summary
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
LIMIT 15;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2.4 Try it yourself
-- MAGIC
-- MAGIC Pick one of the functions above and point it at the data differently. A couple of ideas —
-- MAGIC pick one, or come up with your own:
-- MAGIC
-- MAGIC - Reclassify with a different label set, e.g. `ARRAY('Mortgage/loan issue', 'Bank account issue', 'Card issue', 'Other')`
-- MAGIC - Extract a different field, e.g. `'phone number mentioned'` or `'name of the company representative'`
-- MAGIC - Summarize with a tighter word limit, e.g. `ai_summarize(narrative, 15)`, and see how much detail survives
-- MAGIC
-- MAGIC Fill in the `-- TODO` below and run it — or, if you'd rather explore with autocomplete and
-- MAGIC a schema browser, open **`sql_editor_explore.sql`** (same exercise) in the **SQL editor**
-- MAGIC instead: sidebar → SQL Editor → open the workspace file browser → navigate to this file in
-- MAGIC the Git folder you cloned. The `:catalog` / `:schema` markers show up as fill-in widgets there
-- MAGIC too, same as in this notebook.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2.5 Chaining AI functions: summarize, then classify the summary
-- MAGIC
-- MAGIC So far each function has run independently against the full `narrative`. You can also feed the
-- MAGIC **output** of one AI function into another as input — here, we summarize each complaint first,
-- MAGIC then classify the *summary* (not the original narrative) into an urgency level. The second step
-- MAGIC reasons over a few words instead of a multi-paragraph narrative, which is cheaper and faster
-- MAGIC than re-running against the full text for every downstream question you want answered.
-- MAGIC
-- MAGIC The CTE makes the two steps explicit: `summarized` computes the summary once, and the outer
-- MAGIC `SELECT` classifies `narrative_summary` — not `narrative` — into an urgency level.

-- COMMAND ----------

WITH summarized AS (
  SELECT
    complaint_id,
    product,
    ai_summarize(narrative, 40) AS narrative_summary
  FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
  LIMIT 15
)
SELECT
  complaint_id,
  product,
  narrative_summary,
  ai_classify(narrative_summary, ARRAY('High', 'Medium', 'Low')) AS urgency
FROM summarized;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Next: **03_document_exploration.sql** — running these same kinds of AI functions over
-- MAGIC unstructured documents (PDFs) instead of just text columns.