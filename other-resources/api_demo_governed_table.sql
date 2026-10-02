-- Databricks notebook source
-- MAGIC %md
-- MAGIC # API → governed table — SQL demo
-- MAGIC
-- MAGIC Hands-on companion to the Block 2 slides (**"How data lands in a governed table"** /
-- MAGIC **"Pick the approach that fits"**). This is the **SQL** point on that spectrum: call an
-- MAGIC external REST API directly from a query via `http_request()`, then land the result in a
-- MAGIC governed Unity Catalog table.
-- MAGIC
-- MAGIC **Not a Free Edition notebook.** `CREATE CONNECTION` needs a privilege that may not be
-- MAGIC available there — run this against a standard paid workspace instead (presenter demo only,
-- MAGIC not part of the attendee path).
-- MAGIC
-- MAGIC Data source: [Frankfurter](https://api.frankfurter.dev) — a free, public, **no auth
-- MAGIC required** exchange-rate API. Picked deliberately so this demo needs zero secrets, nothing
-- MAGIC to commit to the repo, nothing to redact before presenting live.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/connection name

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'main';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT connection_name DEFAULT 'frankfurter_api';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Create an HTTP connection
-- MAGIC
-- MAGIC `CREATE CONNECTION` is a Unity Catalog object — governed, auditable, reusable by anyone
-- MAGIC you grant access to, instead of a token pasted into every notebook that needs this API.
-- MAGIC No `bearer_token` option here since Frankfurter doesn't require auth; a real API would add
-- MAGIC one, read from a secret, never hardcoded.

-- COMMAND ----------

CREATE CONNECTION IF NOT EXISTS IDENTIFIER(:connection_name) TYPE HTTP
OPTIONS (
  host 'https://api.frankfurter.dev',
  port '443',
  base_path '/v1/'
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Call the API from SQL
-- MAGIC
-- MAGIC `http_request()` returns a `STRUCT<status_code INT, text STRING>` — `text` is the raw JSON
-- MAGIC response body as a string. Run this first to see the actual shape before parsing it.

-- COMMAND ----------

SELECT
  http_request(
    conn    => :connection_name,
    method  => 'GET',
    path    => 'latest',
    params  => map('base', 'USD', 'symbols', 'GBP,EUR,JPY')
  ) AS response;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Parse the response and land it in a governed table
-- MAGIC
-- MAGIC `response.text` is a JSON string — `:` VARIANT path syntax pulls fields out of it directly,
-- MAGIC no schema to declare up front. `variant_explode` turns the `rates` object into one row per
-- MAGIC currency, the same table-valued function used for `ai_parse_document` output in Block 4.
-- MAGIC
-- MAGIC This is a `CREATE OR REPLACE TABLE` on purpose: re-running the demo live shouldn't leave
-- MAGIC duplicate rows behind. A real pipeline would `MERGE` or append with a captured-at
-- MAGIC timestamp instead — call that out if asked.

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER(:catalog || '.' || :schema || '.fx_rates_demo') AS
WITH raw AS (
  SELECT
    http_request(
      conn    => :connection_name,
      method  => 'GET',
      path    => 'latest',
      params  => map('base', 'USD', 'symbols', 'GBP,EUR,JPY')
    ).text AS response_text
),
parsed AS (
  SELECT parse_json(response_text) AS response_json
  FROM raw
)
SELECT
  response_json:base::STRING   AS base_currency,
  response_json:date::STRING   AS rate_date,
  r.key                        AS target_currency,
  r.value::DOUBLE              AS rate,
  current_timestamp()          AS captured_at
FROM parsed,
LATERAL variant_explode(response_json:rates) AS r;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Verify

-- COMMAND ----------

SELECT *
FROM IDENTIFIER(:catalog || '.' || :schema || '.fx_rates_demo')
ORDER BY target_currency;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Where this sits on the spectrum
-- MAGIC
-- MAGIC `http_request()` is **rate-limited** and documented as built "for interactive and
-- MAGIC agent-based use cases, not high-volume batch queries" — Databricks' own docs recommend the
-- MAGIC Unity Catalog connections proxy endpoint with the provider's SDK for production-scale
-- MAGIC ingestion instead. That's the point of this demo: this is the simplest, fastest way to get
-- MAGIC *something* from an API into a governed table — exactly the "SQL" box on the spectrum
-- MAGIC slide, not a replacement for Lakeflow Connect or a declarative pipeline at real volume.
