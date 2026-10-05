-- 2.4 Try it yourself — SQL editor version
--
-- This is the same exercise as section 2.4 in 02_ai_functions.sql, meant to be opened
-- directly in the SQL editor instead of a notebook cell — you get autocomplete, the
-- schema browser, and inline docs on hover, which are handy while you're poking around.
--
-- To open it: sidebar → SQL Editor → use the workspace file browser to navigate to this
-- file inside the Git folder you cloned, then open it. The :catalog / :schema markers
-- below show up as fill-in widgets at the top of the editor the first time you run this —
-- set them to match whatever you used in 01_ingest_data.sql (defaults: workspace / workshop).

-- Pick one of the functions below and point it at the data differently. A couple of ideas —
-- pick one, or come up with your own:
--   - Reclassify with a different label set, e.g. ARRAY('Mortgage/loan issue', 'Bank account issue', 'Card issue', 'Other')
--   - Extract a different field, e.g. 'phone number mentioned' or 'name of the company representative'
--   - Summarize with a tighter word limit, e.g. ai_summarize(narrative, 15), and see how much detail survives

-- TODO: write your own ai_classify / ai_extract / ai_summarize call here
SELECT
  complaint_id,
  narrative
  -- , ai_classify(narrative, ARRAY( /* your labels here */ )) AS my_category
FROM IDENTIFIER(:catalog || '.' || :schema || '.complaints')
LIMIT 10;
