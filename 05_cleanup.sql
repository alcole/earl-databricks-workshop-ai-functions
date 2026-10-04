-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 5. Clean up
-- MAGIC
-- MAGIC Removes everything the workshop notebooks created, so your workspace is back where it started:
-- MAGIC
-- MAGIC - the Jobs from `04_pipelines_jobs.sql` (`workshop-classify-complaints-<schema>` and
-- MAGIC   `workshop-classify-on-arrival-<schema>` — the file-arrival one keeps watching the Volume
-- MAGIC   until it's deleted)
-- MAGIC - the SQL Editor query you saved in `04_pipelines_jobs.sql` (if you paste its ID below)
-- MAGIC - the workshop schema, including the `complaints` table and the Volume with the CSV and
-- MAGIC   invoice PDFs
-- MAGIC
-- MAGIC The catalog itself is left alone — `workspace` is your workspace's default catalog.
-- MAGIC
-- MAGIC **This can't be undone.** Set the widgets to match what you used in the other notebooks, then
-- MAGIC type `DELETE` into the `confirm` widget and run all.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT query_id DEFAULT '';
CREATE WIDGET TEXT confirm DEFAULT '';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Delete the Jobs and the saved query
-- MAGIC Jobs go first: the file-arrival job watches the Volume we're about to drop. If you ran
-- MAGIC `04_pipelines_jobs.sql` more than once there may be several jobs with the same name — this
-- MAGIC deletes all of them.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC from databricks.sdk import WorkspaceClient
-- MAGIC
-- MAGIC assert dbutils.widgets.get("confirm") == "DELETE", "Type DELETE into the confirm widget to run the cleanup."
-- MAGIC
-- MAGIC schema = dbutils.widgets.get("schema")
-- MAGIC query_id = dbutils.widgets.get("query_id")
-- MAGIC
-- MAGIC w = WorkspaceClient()
-- MAGIC
-- MAGIC for name in (f"workshop-classify-complaints-{schema}", f"workshop-classify-on-arrival-{schema}"):
-- MAGIC     for job in w.jobs.list(name=name):
-- MAGIC         w.jobs.delete(job_id=job.job_id)
-- MAGIC         print(f"Deleted job {job.job_id} ({name})")
-- MAGIC
-- MAGIC if query_id:
-- MAGIC     w.queries.delete(id=query_id)
-- MAGIC     print(f"Moved query {query_id} to trash")
-- MAGIC else:
-- MAGIC     print("No query_id set — delete the saved query from the SQL Editor yourself if you made one.")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Drop the schema
-- MAGIC `CASCADE` drops everything inside it too — the `complaints` table and the Volume, along with
-- MAGIC the files stored in it.

-- COMMAND ----------

SELECT CASE WHEN :confirm != 'DELETE'
  THEN raise_error('Type DELETE into the confirm widget to run the cleanup.')
END;

DROP SCHEMA IF EXISTS IDENTIFIER(:catalog || '.' || :schema) CASCADE;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Anything made in the UI
-- MAGIC The Genie Agent and AI/BI dashboard from Block 5 were built by hand, so delete them by hand:
-- MAGIC open each from the sidebar (**Genie** / **Dashboards**) and use the kebab menu → **Move to trash**.
