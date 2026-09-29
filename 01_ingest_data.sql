-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 1. Ingest workshop data
-- MAGIC
-- MAGIC **Before running this notebook:**
-- MAGIC 1. Download `complaints_sample.csv` from:
-- MAGIC    `https://raw.githubusercontent.com/alcole/earl-databricks-workshop-ai-functions/main/complaints_sample.csv`
-- MAGIC 2. Update the `catalog` / `schema` / `volume` widgets below if you don't want the defaults
-- MAGIC 3. Run the notebook — it creates the schema and Volume for you, then you'll upload the CSV into that Volume via Catalog Explorer's **Upload** button before the `LIST` cell

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/volume
-- MAGIC Edit these three widgets to match your own workspace before running the rest of the notebook.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'main';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT volume DEFAULT 'workshop_data';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Create the schema and Volume
-- MAGIC Safe to re-run — `IF NOT EXISTS` means this won't touch anything that's already there.

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:catalog || '.' || :schema);

CREATE VOLUME IF NOT EXISTS IDENTIFIER(:catalog || '.' || :schema || '.' || :volume);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Confirm the file landed in the Volume
-- MAGIC If this errors, upload `complaints_sample.csv` into the Volume via Catalog Explorer's **Upload** button first.

-- COMMAND ----------

LIST '/Volumes/${catalog}/${schema}/${volume}/';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Load into a managed table
-- MAGIC `COPY INTO` is idempotent — safe to re-run if something goes wrong partway through.
-- MAGIC
-- MAGIC The source CSV's narrative column is called `consumer_complaint_narrative` — renamed to
-- MAGIC `narrative` here via the `SELECT` wrapper so the rest of the workshop has a short, stable name.
-- MAGIC
-- MAGIC Narratives contain literal newlines inside quoted fields, so `multiLine = 'true'` is required —
-- MAGIC without it Spark's CSV reader splits mid-record on those newlines and scrambles every column.
-- MAGIC
-- MAGIC The file also escapes embedded quotes the standard CSV way (`""`), but Spark's CSV reader
-- MAGIC defaults `escape` to a backslash — so `escape = '"'` is required too, or any narrative
-- MAGIC containing a quote character truncates its row early and shifts every column after it.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS IDENTIFIER(:catalog || '.' || :schema || '.complaints') (
  complaint_id STRING,
  date_received STRING,
  product STRING,
  sub_product STRING,
  issue STRING,
  sub_issue STRING,
  narrative STRING,
  company STRING,
  state STRING,
  submitted_via STRING,
  company_response_to_consumer STRING,
  tags STRING
);

-- COMMAND ----------

COPY INTO ${catalog}.${schema}.complaints
FROM (
  SELECT
    complaint_id,
    date_received,
    product,
    sub_product,
    issue,
    sub_issue,
    consumer_complaint_narrative AS narrative,
    company,
    state,
    submitted_via,
    company_response_to_consumer,
    tags
  FROM '/Volumes/${catalog}/${schema}/${volume}/complaints_sample.csv'
)
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'false', 'multiLine' = 'true', 'escape' = '"')
COPY_OPTIONS ('mergeSchema' = 'true');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Quick sanity check
-- MAGIC Confirms the load worked and gives a first feel for the data before we start running AI functions on it.

-- COMMAND ----------

SELECT COUNT(*) AS total_rows FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints');

-- COMMAND ----------

SELECT product, COUNT(*) AS complaint_count
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
GROUP BY product
ORDER BY complaint_count DESC;

-- COMMAND ----------

-- A handful of raw narratives, just to see what we're working with
SELECT complaint_id, product, narrative
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
WHERE narrative IS NOT NULL
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Data's loaded. Move to notebook **02_ai_functions.sql** next.