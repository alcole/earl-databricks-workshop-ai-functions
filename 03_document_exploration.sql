-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 3. Document AI: parsing and extracting from PDFs
-- MAGIC
-- MAGIC `02_ai_functions.sql` ran `ai_classify` / `ai_extract` / `ai_summarize` against a text column
-- MAGIC (`narrative`). Those same functions work just as well starting from a **PDF, image, or Office
-- MAGIC document** — you just need to get the document's raw content into a structured form first.
-- MAGIC That's what `ai_parse_document` does: it turns an unstructured document into a structured
-- MAGIC layout (paragraphs, tables, headers, page numbers) that downstream AI functions — or your own
-- MAGIC code — can work with directly.
-- MAGIC
-- MAGIC **Before running this notebook:**
-- MAGIC 1. Download `invoices_workshop.zip` from:
-- MAGIC    `https://raw.githubusercontent.com/alcole/earl-databricks-workshop-ai-functions/main/invoices_workshop.zip`
-- MAGIC 2. Upload it into the same Volume you used in `01_ingest_data.sql`, via Catalog Explorer's
-- MAGIC    **Upload** button (no need to unzip it yourself — the next cell does that on the platform).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/volume
-- MAGIC Match whatever you used in `01_ingest_data.sql`.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'main';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT volume DEFAULT 'workshop_data';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Unzip the sample invoices into the Volume
-- MAGIC Unity Catalog Volumes are just regular paths under `/Volumes/...`, so plain Python file I/O
-- MAGIC (including `zipfile`) works directly against them — no special upload step needed beyond
-- MAGIC getting the zip itself into the Volume.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC import zipfile, os
-- MAGIC
-- MAGIC catalog = dbutils.widgets.get("catalog")
-- MAGIC schema = dbutils.widgets.get("schema")
-- MAGIC volume = dbutils.widgets.get("volume")
-- MAGIC
-- MAGIC volume_path = f"/Volumes/{catalog}/{schema}/{volume}"
-- MAGIC zip_path = f"{volume_path}/invoices_workshop.zip"
-- MAGIC invoices_dir = f"{volume_path}/invoices"
-- MAGIC
-- MAGIC assert os.path.exists(zip_path), f"{zip_path} not found — upload invoices_workshop.zip to the Volume first."
-- MAGIC
-- MAGIC os.makedirs(invoices_dir, exist_ok=True)
-- MAGIC with zipfile.ZipFile(zip_path) as z:
-- MAGIC     z.extractall(invoices_dir)
-- MAGIC
-- MAGIC pdfs = sorted(f for f in os.listdir(invoices_dir) if f.endswith(".pdf"))
-- MAGIC print(f"Extracted {len(pdfs)} PDFs into {invoices_dir}")
-- MAGIC print(pdfs[:5])

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.1 `ai_parse_document` — turn a PDF into structured layout
-- MAGIC
-- MAGIC `READ_FILES(..., format => 'binaryFile')` reads the raw bytes of the file into a `content`
-- MAGIC column; `ai_parse_document` takes that binary content and returns a `VARIANT` describing the
-- MAGIC document's structure — a page list plus an `elements` array, where each element has a `type`
-- MAGIC (`text`, `table`, `title`, `section_header`, ...), its extracted `content`, and a confidence
-- MAGIC score. Tables come back as HTML.

-- COMMAND ----------

SELECT
  path,
  ai_parse_document(content, MAP('version', '2.0')) AS parsed
FROM READ_FILES('/Volumes/${catalog}/${schema}/${volume}/invoices/invoice_001.pdf', format => 'binaryFile');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.2 `ai_extract` on the parsed output
-- MAGIC
-- MAGIC You can hand `ai_extract` the parsed `VARIANT` directly instead of plain text. One difference
-- MAGIC from `02_ai_functions.sql`: when extracting from a parsed document, `ai_extract` wants its
-- MAGIC field list as a **JSON array string of snake_case property names** (e.g.
-- MAGIC `'["invoice_number", "vendor_name"]'`) rather than the `ARRAY('field description', ...)` style
-- MAGIC used against plain text — spaces in the field names aren't accepted here. The result comes
-- MAGIC back wrapped as `{"response": {"field_name": {"value": ...}}, ...}`.

-- COMMAND ----------

WITH parsed_docs AS (
  SELECT
    path,
    ai_parse_document(content, MAP('version', '2.0')) AS parsed_content
  FROM READ_FILES('/Volumes/${catalog}/${schema}/${volume}/invoices/invoice_001.pdf', format => 'binaryFile')
)
SELECT
  path,
  ai_extract(parsed_content, '["invoice_number", "vendor_name", "total_amount"]') AS invoice_data
FROM parsed_docs;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.3 Try it yourself
-- MAGIC
-- MAGIC Same pattern, your turn. A couple of ideas:
-- MAGIC
-- MAGIC - Point at a different file — try `invoice_002.pdf` (or list `${volume}/invoices/` and pick
-- MAGIC   any other one)
-- MAGIC - Extract different fields, e.g. `'["client_name", "date_of_issue"]'` — check the parsed
-- MAGIC   output from 3.1 to see what's actually on the page before you pick field names
-- MAGIC
-- MAGIC Fill in the `-- TODO` below and run it.

-- COMMAND ----------

-- TODO: point this at a different invoice file and/or extract different fields
WITH parsed_docs AS (
  SELECT
    path,
    ai_parse_document(content, MAP('version', '2.0')) AS parsed_content
  FROM READ_FILES('/Volumes/${catalog}/${schema}/${volume}/invoices/invoice_002.pdf', format => 'binaryFile')
)
SELECT
  path,
  ai_extract(parsed_content, '["invoice_number", "client_name", "date_of_issue"]') AS invoice_data
  -- ai_extract(parsed_content, '[ /* your fields here */ ]') AS my_extract
FROM parsed_docs;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.4 Still have time? More to explore on `complaints`
-- MAGIC
-- MAGIC This whole block is designed to flex with however much time is left in the session. If the
-- MAGIC room still has appetite, jump back to the `complaints` table from `01_ingest_data.sql` and
-- MAGIC push the same functions further — these are stubs, not full working examples, so treat them
-- MAGIC as starting points:
-- MAGIC
-- MAGIC - **Different classification scheme** — instead of the billing/fraud/etc. categories from
-- MAGIC   `02_ai_functions.sql`, try classifying by likely resolution difficulty:
-- MAGIC   `ai_classify(narrative, ARRAY('Quick fix', 'Needs investigation', 'Likely dispute'))`
-- MAGIC - **A different extracted field** — `ai_extract(narrative, ARRAY('name of a specific person mentioned'))`
-- MAGIC   or `ai_extract(narrative, ARRAY('account or reference number mentioned'))`
-- MAGIC - **Combine with what you just learned here** — pick one complaint's `narrative`, run it through
-- MAGIC   `ai_summarize`, then `ai_classify` the summary the same way `02_ai_functions.sql`'s chaining
-- MAGIC   example did — but this time split by `state` or `company` instead of urgency.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Next: **04_pipelines_jobs.sql** — turning one of these queries into a scheduled or
-- MAGIC triggered pipeline.
