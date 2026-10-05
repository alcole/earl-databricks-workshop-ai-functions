-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 1. Ingest workshop data
-- MAGIC
-- MAGIC **Before running this notebook:**
-- MAGIC 1. Update the `catalog` / `schema` / `volume` widgets below if you don't want the defaults
-- MAGIC 2. Run the notebook — it creates the schema and Volume for you, then copies `complaints_sample.csv`
-- MAGIC    and `invoices_workshop.zip` from your cloned Git folder into the Volume
-- MAGIC
-- MAGIC If the copy can't find the files, download them from
-- MAGIC `https://raw.githubusercontent.com/alcole/earl-databricks-workshop-ai-functions/main/<file>`
-- MAGIC and upload them into the Volume via Catalog Explorer's **Upload** button.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/volume
-- MAGIC Edit these three widgets to match your own workspace before running the rest of the notebook.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';
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
-- MAGIC ### Get the workshop files into the Volume
-- MAGIC Copies `complaints_sample.csv` (used here) and `invoices_workshop.zip` (used in
-- MAGIC `03_document_exploration.sql`) from the Git folder you cloned into the Volume, then unzips the
-- MAGIC invoices. Unity Catalog Volumes are just regular paths under `/Volumes/...`, so plain Python
-- MAGIC file I/O works directly against them. If a file can't be found, upload it via Catalog
-- MAGIC Explorer's **Upload** button and re-run.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import os, shutil, zipfile
-- MAGIC from databricks.sdk import WorkspaceClient
-- MAGIC
-- MAGIC catalog = dbutils.widgets.get("catalog")
-- MAGIC schema = dbutils.widgets.get("schema")
-- MAGIC volume = dbutils.widgets.get("volume")
-- MAGIC
-- MAGIC volume_path = f"/Volumes/{catalog}/{schema}/{volume}"
-- MAGIC search_dir = f"/Workspace/Users/{WorkspaceClient().current_user.me().user_name}"
-- MAGIC
-- MAGIC def copy_to_volume(filename):
-- MAGIC     """Copy filename from the cloned Git folder into the Volume, unless it's already there."""
-- MAGIC     target = f"{volume_path}/{filename}"
-- MAGIC     if os.path.exists(target):
-- MAGIC         return target
-- MAGIC     for dirpath, dirnames, filenames in os.walk(search_dir):
-- MAGIC         if filename in filenames:
-- MAGIC             shutil.copy(os.path.join(dirpath, filename), target)
-- MAGIC             print(f"Copied {filename} from {dirpath} to {target}")
-- MAGIC             return target
-- MAGIC         if dirpath[len(search_dir):].count(os.sep) >= 3:
-- MAGIC             dirnames.clear()
-- MAGIC     raise FileNotFoundError(f"{target} not found and {filename} not found under {search_dir}.")
-- MAGIC
-- MAGIC copy_to_volume("complaints_sample.csv")
-- MAGIC zip_path = copy_to_volume("invoices_workshop.zip")
-- MAGIC
-- MAGIC invoices_dir = f"{volume_path}/invoices"
-- MAGIC os.makedirs(invoices_dir, exist_ok=True)
-- MAGIC with zipfile.ZipFile(zip_path) as z:
-- MAGIC     z.extractall(invoices_dir)
-- MAGIC pdfs = sorted(f for f in os.listdir(invoices_dir) if f.endswith(".pdf"))
-- MAGIC print(f"Extracted {len(pdfs)} PDFs into {invoices_dir}")
-- MAGIC
-- MAGIC display(dbutils.fs.ls(volume_path))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Load into a managed table
-- MAGIC `CREATE OR REPLACE TABLE ... AS SELECT` rebuilds the table from the file each time, so it's
-- MAGIC safe to re-run if something goes wrong partway through. `read_files` takes the Volume path as
-- MAGIC a normal expression, so the `:catalog` / `:schema` / `:volume` widgets plug straight in.
-- MAGIC
-- MAGIC The source CSV's narrative column is called `consumer_complaint_narrative` — renamed to
-- MAGIC `narrative` here so the rest of the workshop has a short, stable name. `inferColumnTypes =>
-- MAGIC false` keeps every column as `STRING`.
-- MAGIC
-- MAGIC Narratives contain literal newlines inside quoted fields, so `multiLine => true` is required —
-- MAGIC without it Spark's CSV reader splits mid-record on those newlines and scrambles every column.
-- MAGIC
-- MAGIC The file also escapes embedded quotes the standard CSV way (`""`), but Spark's CSV reader
-- MAGIC defaults `escape` to a backslash — so `escape => '"'` is required too, or any narrative
-- MAGIC containing a quote character truncates its row early and shifts every column after it.

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :schema || '.complaints') AS
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
FROM read_files(
  '/Volumes/' || :catalog || '/' || :schema || '/' || :volume || '/complaints_sample.csv',
  format => 'csv',
  header => true,
  inferColumnTypes => false,
  multiLine => true,
  escape => '"'
);

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