-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 3. Automate the input: turning an AI function query into a Job
-- MAGIC
-- MAGIC `02_ai_functions.sql` ran everything by hand, one cell at a time. That's fine for exploring,
-- MAGIC but it doesn't scale — every time new complaints land in the Volume, someone has to remember
-- MAGIC to re-open the notebook and re-run the cells. A **Job** runs a piece of work on a schedule, on
-- MAGIC demand via an API call, or — what we'll build here — automatically when a new file lands.
-- MAGIC
-- MAGIC **A constraint worth knowing up front:** a Databricks Job's `sql_task` runs a *saved query* —
-- MAGIC it takes a `query_id`, not inline SQL text. You can't hand a job a raw `SELECT ...` string the
-- MAGIC way you can with a notebook task. So the first step below is a short, one-time UI step: save
-- MAGIC the classify query from `02_ai_functions.sql` as a query object in the SQL Editor, then hand
-- MAGIC its ID to the code in this notebook.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Set your catalog/schema/volume
-- MAGIC Match whatever you used in `01_ingest_data.sql`. Leave `query_id` blank for now — you'll fill
-- MAGIC it in after the next step.

-- COMMAND ----------

CREATE WIDGET TEXT catalog DEFAULT 'workspace';
CREATE WIDGET TEXT schema DEFAULT 'workshop';
CREATE WIDGET TEXT volume DEFAULT 'workshop_data';
CREATE WIDGET TEXT query_id DEFAULT '';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.1 Save the classify query
-- MAGIC
-- MAGIC Run the cell below to preview the query in this notebook — it's the same `ai_classify` query
-- MAGIC from `02_ai_functions.sql`, parameterized with `:catalog` / `:schema` markers — the same
-- MAGIC `:name` syntax works both here (bound to the widgets) and in the SQL Editor (as query parameters).

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
LIMIT 25;

-- COMMAND ----------

-- DBTITLE 1,Cell 6
-- MAGIC %md
-- MAGIC Now save it as a query object so a Job can reference it:
-- MAGIC
-- MAGIC 1. Open **SQL Editor** in the left sidebar (a separate area from this notebook).
-- MAGIC 2. Start a **New query**, and paste in this exact text:
-- MAGIC    ```sql
-- MAGIC    SELECT
-- MAGIC      complaint_id,
-- MAGIC      product,
-- MAGIC      ai_classify(
-- MAGIC        narrative,
-- MAGIC        ARRAY(
-- MAGIC          'Billing or fee dispute',
-- MAGIC          'Debt collection practices',
-- MAGIC          'Fraud or unauthorized transaction',
-- MAGIC          'Credit reporting error',
-- MAGIC          'Customer service quality',
-- MAGIC          'Other'
-- MAGIC        )
-- MAGIC      ) AS category
-- MAGIC    FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
-- MAGIC    LIMIT 25
-- MAGIC    ```
-- MAGIC 3. The SQL Editor auto-detects the `:catalog` and `:schema` markers and offers them as **query
-- MAGIC    parameters** in a panel on the right — set their default values to match the widgets above
-- MAGIC    (e.g. `workspace` / `workshop`). This matters: a Job runs unattended, so the query needs usable
-- MAGIC    defaults rather than relying on someone typing values into a prompt.
-- MAGIC 4. Pick the same SQL warehouse you've been using, then **Save As** — give it the **exact** name
-- MAGIC    `workshop-classify-complaints`. The code in section 3.2 looks up the query by this name, so the
-- MAGIC    spelling must match.
-- MAGIC
-- MAGIC That's it — no need to hunt for a UUID. The next section finds the saved query by name
-- MAGIC automatically using the Databricks SDK.
-- MAGIC
-- MAGIC This is the one part of the pipeline that has to happen by hand in the UI — there's no
-- MAGIC notebook cell that can create a SQL Editor query on your behalf.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.2 Create and run a Job from Python
-- MAGIC
-- MAGIC Everything past this point is scriptable. We'll use the Databricks SDK to create a Job whose
-- MAGIC only task is `sql_task` pointed at the query you just saved, trigger it immediately with
-- MAGIC `run_now`, and poll until it finishes.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC %pip install -q databricks-sdk

-- COMMAND ----------

-- MAGIC %python
-- MAGIC dbutils.library.restartPython()

-- COMMAND ----------

-- DBTITLE 1,Cell 10
-- MAGIC %python
-- MAGIC import time
-- MAGIC from databricks.sdk import WorkspaceClient
-- MAGIC from databricks.sdk.service import jobs
-- MAGIC
-- MAGIC catalog = dbutils.widgets.get("catalog")
-- MAGIC schema = dbutils.widgets.get("schema")
-- MAGIC volume = dbutils.widgets.get("volume")
-- MAGIC w = WorkspaceClient()
-- MAGIC
-- MAGIC # Find the saved query by name so workshop attendees don't have to hunt for a UUID.
-- MAGIC query_id = dbutils.widgets.get("query_id")
-- MAGIC if not query_id:
-- MAGIC     _matching = [q for q in w.queries.list() if q.name == "workshop-classify-complaints"]
-- MAGIC     assert _matching, "No query named 'workshop-classify-complaints' found. Save it in the SQL Editor first (see step 3.1)."
-- MAGIC     query_id = _matching[0].id
-- MAGIC     print(f"Auto-detected query_id: {query_id}")
-- MAGIC
-- MAGIC # Reuse whichever SQL warehouse is already running this notebook's queries, rather than
-- MAGIC # hardcoding an ID that would only be valid in one workspace.
-- MAGIC warehouse_id = w.warehouses.list()[0].id
-- MAGIC
-- MAGIC job = w.jobs.create(
-- MAGIC     name=f"workshop-classify-complaints-{schema}",
-- MAGIC     tasks=[
-- MAGIC         jobs.Task(
-- MAGIC             task_key="classify_complaints",
-- MAGIC             sql_task=jobs.SqlTask(
-- MAGIC                 query=jobs.SqlTaskQuery(query_id=query_id),
-- MAGIC                 warehouse_id=warehouse_id,
-- MAGIC                 parameters={
-- MAGIC                     "catalog": catalog,
-- MAGIC                     "schema": schema,
-- MAGIC                 },
-- MAGIC             ),
-- MAGIC         )
-- MAGIC     ],
-- MAGIC )
-- MAGIC print(f"Created job {job.job_id}")
-- MAGIC
-- MAGIC run = w.jobs.run_now(job_id=job.job_id)
-- MAGIC print(f"Triggered run {run.run_id}")
-- MAGIC
-- MAGIC terminal_states = {
-- MAGIC     jobs.RunLifeCycleState.TERMINATED,
-- MAGIC     jobs.RunLifeCycleState.SKIPPED,
-- MAGIC     jobs.RunLifeCycleState.INTERNAL_ERROR,
-- MAGIC }
-- MAGIC run_status = w.jobs.get_run(run.run_id)
-- MAGIC while run_status.state.life_cycle_state not in terminal_states:
-- MAGIC     print(f"...still running ({run_status.state.life_cycle_state.value})")
-- MAGIC     time.sleep(10)
-- MAGIC     run_status = w.jobs.get_run(run.run_id)
-- MAGIC
-- MAGIC result_state = run_status.state.result_state
-- MAGIC print(f"Finished: {run_status.state.life_cycle_state.value} / {result_state.value if result_state else 'n/a'}")
-- MAGIC
-- MAGIC # Hand these off to the SQL verification cell below.
-- MAGIC dbutils.widgets.text("last_job_id", str(job.job_id))
-- MAGIC dbutils.widgets.text("last_run_id", str(run.run_id))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.3 Automate it for real: a file-arrival trigger
-- MAGIC
-- MAGIC `run_now` is a manual trigger — someone (or something) still has to call it. For "reprocess
-- MAGIC automatically when new data lands," a **file-arrival trigger** watches a Unity Catalog Volume
-- MAGIC path and starts the job on its own when a new file appears there, instead of on a schedule.
-- MAGIC
-- MAGIC **This was tested live against this Free Edition workspace while building this notebook — it
-- MAGIC does work** (a job with a file-arrival trigger on this Volume path fired correctly and
-- MAGIC completed with `SUCCESS`). The one thing worth setting expectations on: file-arrival triggers
-- MAGIC are documented as "best effort, checked about once a minute," and in testing here the first
-- MAGIC fire took a few minutes end to end, not seconds. That's too slow to casually demo live and
-- MAGIC just watch it happen — if you want a live payoff, kick this cell off *before* you start talking
-- MAGIC through 3.1–3.2, then circle back to check on it. Otherwise, treat the cell below as reference
-- MAGIC code to read rather than something to run-and-wait-on in the room.

-- COMMAND ----------

-- DBTITLE 1,Cell 12
-- MAGIC %python
-- MAGIC trigger_job = w.jobs.create(
-- MAGIC     name=f"workshop-classify-on-arrival-{schema}",
-- MAGIC     tasks=[
-- MAGIC         jobs.Task(
-- MAGIC             task_key="classify_complaints",
-- MAGIC             sql_task=jobs.SqlTask(
-- MAGIC                 query=jobs.SqlTaskQuery(query_id=query_id),
-- MAGIC                 warehouse_id=warehouse_id,
-- MAGIC                 parameters={
-- MAGIC                     "catalog": catalog,
-- MAGIC                     "schema": schema,
-- MAGIC                 },
-- MAGIC             ),
-- MAGIC         )
-- MAGIC     ],
-- MAGIC     trigger=jobs.TriggerSettings(
-- MAGIC         file_arrival=jobs.FileArrivalTriggerConfiguration(
-- MAGIC             url=f"/Volumes/{catalog}/{schema}/{volume}/",
-- MAGIC             # Uncomment to rate-limit if files tend to land in bursts:
-- MAGIC             # min_time_between_triggers_seconds=900,
-- MAGIC             # wait_after_last_change_seconds=60,
-- MAGIC         ),
-- MAGIC         pause_status=jobs.PauseStatus.UNPAUSED,
-- MAGIC     ),
-- MAGIC )
-- MAGIC print(f"Created file-arrival-triggered job {trigger_job.job_id}")
-- MAGIC print(f"Watching /Volumes/{catalog}/{schema}/{volume}/ — drop a new file there to fire it.")
-- MAGIC
-- MAGIC # Housekeeping for a workshop: this job stays around (and keeps watching the Volume) until
-- MAGIC # someone deletes it. Clean up after the session with:
-- MAGIC # w.jobs.delete(job_id=trigger_job.job_id)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3.4 Verify the run actually happened
-- MAGIC
-- MAGIC Query the job's run history through the SDK — this hits the live Jobs API, not a downstream
-- MAGIC system table, so there's no reporting lag to worry about.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC runs = w.jobs.list_runs(job_id=job.job_id)
-- MAGIC for r in runs:
-- MAGIC     rs = r.state.result_state.value if r.state.result_state else "n/a"
-- MAGIC     print(f"run_id={r.run_id}  life_cycle={r.state.life_cycle_state.value}  result={rs}  trigger={r.trigger.value if r.trigger else 'n/a'}")

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Next: **R demo** (presenter), then **Genie + dashboard**.