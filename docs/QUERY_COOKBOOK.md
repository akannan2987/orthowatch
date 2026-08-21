[← README](../README.md) · [All docs in order](../README.md#the-tutorial-in-order) · [Glossary](GLOSSARY.md)

# The SQL cookbook — ready-to-run queries for the Query tab

Every query below runs as-is in the app's **Query** tab (read-only
by construction; results cap at 200 rows — add `WHERE`/`LIMIT` to
narrow). Copy, paste, Run — or use the tab's **"Load an example"**
picker, which serves the starred (★) ones. Results download as
CSV/Excel right under the table.

**The one thing to know first — vintages:** the three result tables
(`monthly_trends`, `signal_stats`, `narrative_terms`) hold EVERY
kept run's results, told apart by `run_id`. Query them without a
`run_id` filter and you get all vintages mixed together. The idiom
for "the latest run only":

```sql
WHERE run_id = (SELECT MAX(run_id) FROM monthly_trends)
```

The event tables (`clean_events`, `raw_events`) and the ledger
(`run_history`) are unversioned — no filter needed.

---

## Exploring the events

**★ How many reports per family?**
```sql
SELECT device_family, COUNT(*) AS reports
FROM clean_events GROUP BY device_family ORDER BY reports DESC
```

**Reports per year, per family** (the dataset's shape at a glance):
```sql
SELECT substr(year_month, 1, 4) AS year, device_family, COUNT(*) AS n
FROM clean_events GROUP BY year, device_family ORDER BY year, device_family
```

**★ What kinds of events?** (Injury vs Malfunction vs Death mix)
```sql
SELECT device_family, event_type, COUNT(*) AS n
FROM clean_events GROUP BY device_family, event_type
ORDER BY device_family, n DESC
```

**Top manufacturers by report volume** (reporting behavior, not
safety — the honesty note applies to every query here):
```sql
SELECT manufacturer, COUNT(*) AS reports
FROM clean_events GROUP BY manufacturer ORDER BY reports DESC LIMIT 20
```

**★ Most-reported problem codes in one family:**
```sql
SELECT product_problems, COUNT(*) AS n
FROM clean_events WHERE device_family = 'Hip prosthesis'
GROUP BY product_problems ORDER BY n DESC LIMIT 20
```

**Read narratives mentioning a word** (text search; slow-ish on 84K
rows — expect a few seconds):
```sql
SELECT report_number, device_family, substr(narrative, 1, 300) AS excerpt
FROM clean_events WHERE narrative LIKE '%cobalt%' LIMIT 10
```

## Trends

**★ Every flagged month, worst first** (the towers):
```sql
SELECT device_family, year_month, n, status
FROM monthly_trends
WHERE run_id = (SELECT MAX(run_id) FROM monthly_trends)
  AND status != 'within limits'
ORDER BY n DESC
```

**One family's full trend line:**
```sql
SELECT year_month, n, center, ucl, lcl, status
FROM monthly_trends
WHERE run_id = (SELECT MAX(run_id) FROM monthly_trends)
  AND device_family = 'Spinal fixation'
ORDER BY year_month
```

## Signals

**★ All Evans signals for one family, strongest first:**
```sql
SELECT product_problem, a, ROUND(prr, 1) AS prr, ROUND(ror, 1) AS ror
FROM signal_stats
WHERE run_id = (SELECT MAX(run_id) FROM signal_stats)
  AND evans_signal = 1 AND device_family = 'Hip prosthesis'
ORDER BY prr DESC
```

**Signal counts per family** (how concentrated is each family's
problem profile?):
```sql
SELECT device_family, COUNT(*) AS evans_signals
FROM signal_stats
WHERE run_id = (SELECT MAX(run_id) FROM signal_stats)
  AND evans_signal = 1
GROUP BY device_family ORDER BY evans_signals DESC
```

## Narrative vocabulary

**★ A family's most distinctive words** (highest rate-ratio vs all
other families, among words it uses often):
```sql
SELECT word, n, ROUND(per_10k, 1) AS per_10k, ROUND(ratio, 1) AS ratio
FROM narrative_terms
WHERE run_id = (SELECT MAX(run_id) FROM narrative_terms)
  AND device_family = 'Spinal fixation' AND per_10k >= 1
ORDER BY ratio DESC LIMIT 20
```

## Provenance & vintages (the ledger)

**★ What ran, when, with what outcome?**
```sql
SELECT run_at, kind, detail, outcome, seconds
FROM run_history ORDER BY run_at DESC
```

**Which vintages exist, and how big is each?**
```sql
SELECT run_id, COUNT(*) AS rows
FROM monthly_trends GROUP BY run_id ORDER BY run_id DESC
```

**Compare two vintages of one family's flags** (before/after a
refresh or scope change — the selector's question, answered in SQL):
```sql
SELECT run_id, COUNT(*) AS flagged_months
FROM monthly_trends
WHERE device_family = 'Bone plate' AND status != 'within limits'
GROUP BY run_id ORDER BY run_id DESC
```

## Data quality

**Duplicate report_numbers surviving in raw** (the dedup's
workload; clean_events should have none):
```sql
SELECT report_number, COUNT(*) AS copies
FROM raw_events GROUP BY report_number HAVING copies > 1
ORDER BY copies DESC LIMIT 10
```

**Reports with no usable narrative:**
```sql
SELECT device_family, COUNT(*) AS no_narrative
FROM clean_events WHERE narrative IS NULL OR narrative = ''
GROUP BY device_family
```

---

**Why some queries are refused:** the console runs a single
SELECT/WITH on a read-only connection — two independent locks
(doc 09). `DELETE`, `UPDATE`, multiple statements, and PRAGMAs are
refused by design; that refusal is a feature working.

**Next:** back to [the tutorial index](../README.md#the-tutorial-in-order).
