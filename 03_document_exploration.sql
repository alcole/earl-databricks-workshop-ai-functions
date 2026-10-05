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
-- MAGIC **Before running this notebook:** run `01_ingest_data.sql` — it copies `invoices_workshop.zip`
-- MAGIC into the Volume and unzips the sample invoices into `invoices/`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/volume
-- MAGIC Match whatever you used in `01_ingest_data.sql`.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT volume DEFAULT 'workshop_data';

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

-- DBTITLE 1,Cell 5
SELECT
  path,
  CAST(ai_parse_document(content, MAP('version', '2.0')) AS STRING) AS parsed
FROM READ_FILES(
  '/Volumes/' || :catalog || '/' || :schema || '/' || :volume || '/invoices/invoice_001.pdf',
  format => 'binaryFile'
);

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

-- DBTITLE 1,Cell 7
WITH parsed_docs AS (
  SELECT
    path,
    ai_parse_document(content, MAP('version', '2.0')) AS parsed_content
  FROM READ_FILES(
    '/Volumes/' || :catalog || '/' || :schema || '/' || :volume || '/invoices/invoice_001.pdf',
    format => 'binaryFile'
  )
)
SELECT
  path,
  CAST(ai_extract(parsed_content, '["invoice_number", "vendor_name", "total_amount"]') AS STRING) AS invoice_data
FROM parsed_docs;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.3 Try it yourself
-- MAGIC
-- MAGIC Same pattern, your turn. A couple of ideas:
-- MAGIC
-- MAGIC - Point at a different file — try `invoice_002.pdf` (or list the `invoices/` folder in your Volume and pick
-- MAGIC   any other one)
-- MAGIC - Extract different fields, e.g. `'["client_name", "date_of_issue"]'` — check the parsed
-- MAGIC   output from 3.1 to see what's actually on the page before you pick field names
-- MAGIC
-- MAGIC Fill in the `-- TODO` below and run it.

-- COMMAND ----------

-- DBTITLE 1,Cell 9
-- TODO: point this at a different invoice file and/or extract different fields
WITH parsed_docs AS (
  SELECT
    path,
    ai_parse_document(content, MAP('version', '2.0')) AS parsed_content
  FROM READ_FILES(
    '/Volumes/' || :catalog || '/' || :schema || '/' || :volume || '/invoices/invoice_002.pdf',
    format => 'binaryFile'
  )
)
SELECT
  path,
  CAST(ai_extract(parsed_content, '["invoice_number", "client_name", "date_of_issue"]') AS STRING) AS invoice_data
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
-- MAGIC Next: <a href="$./04_pipelines_jobs">04_pipelines_jobs.sql</a> — turning one of these queries
-- MAGIC into a scheduled or triggered pipeline.