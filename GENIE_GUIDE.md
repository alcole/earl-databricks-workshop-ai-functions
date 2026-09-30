# Genie: ask `main.workshop.complaints` questions in plain English

Genie is a click-through, no-SQL way to ask natural-language questions of a table — you point
it at data once, then just type questions. This activity isn't a notebook; everything happens in
the Databricks UI. Complete `01_ingest_data.sql` first so `main.workshop.complaints` exists.

## Create your Genie space

1. In the left sidebar, click **New** → **Genie space** (older UI: search "Genie" in the sidebar
   search box if you don't see it directly).
2. Give it a title, e.g. `Complaints Explorer`.
3. Under the space's data sources, click **Add tables** / **Add data**, and browse to
   catalog `main` → schema `workshop` → table `complaints`. Add it.
4. Pick the SQL warehouse you've been using for the rest of the workshop.
5. Click **Create** (or **Save**).
6. A chat panel opens — type a question and hit enter.

## Troubleshooting

- **"tables must be sorted by identifier" error** — this only happens if a Genie space is
  created or updated via the REST API/CLI with more than one table listed out of alphabetical
  order. You won't hit this clicking through the UI with a single table; it only matters if you
  (or the presenter) later manage a space programmatically — in that case, list tables
  alphabetically by full name (`catalog.schema.table`).
- **Genie can't find the table / gives an empty or generic answer** — double-check you added
  `main.workshop.complaints` specifically, not a different catalog/schema. Use whatever
  `catalog`/`schema` widget values you set in `01_ingest_data.sql`.
- **A question about "categories" comes back empty** — the table doesn't have a pre-computed
  category column; `product` and `issue` are the closest real columns. Ask about those, or run
  `02_ai_functions.sql`'s classify query first if you want an actual category label to query.

## Example questions to try

1. **"How many complaints are in this table?"** — trivial sanity check that Genie is wired up
   correctly. Answer: 831.
2. **"Which company received the most complaints, and how many?"** — single-column aggregation.
   Answer: Experian, 55.
3. **"Which state has the most billing dispute complaints?"** — Genie has to recognize that
   "billing dispute(s)" is a real value in the `issue` column, then group and rank by state.
   Answer: NY, 4.
4. **"Break down complaint counts by product for California only, highest first"** — a filter
   plus an aggregation across two columns; Genie typically also renders a chart for this one.
   Answer: Mortgage (37), Debt collection (25), Credit reporting (16), ...

All four were run against a real test space before writing this guide — these aren't
hypothetical, the numbers above are verified. One thing worth knowing: since this space only has
the one `complaints` table, none of the above involve an actual SQL `JOIN` — they're all
filter/aggregate patterns. If you want to demo a real join live, add a second table to the space
first.
