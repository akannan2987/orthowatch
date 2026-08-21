# OrthoWatch release notes

## v1.0.1 — 2026-08-22

- `setup.sh`: one-command dependency setup for a fresh clone
  (Python venv + requirements.txt; R packages via `renv::restore()`).
  Installs dependencies only — data fetching stays a deliberate,
  documented step.
- README gains a Quick start; roadmap gains the installable-package
  / Docker rung (a 2.0-scale reorganization, honestly deferred).

## v1.0.0 — 2026-08-21 — "The finished instrument"

First stable release. From an empty laptop to a post-market
surveillance instrument over 84,547 FDA MAUDE orthopedic device
reports (2020–2024), built phase by phase and documented as a
beginner-readable tutorial throughout.

**The instrument**
- Ingestion: resilient openFDA client (paging, retries, API key,
  query dictionary, validated scoped fetches, dry-run) → SQLite.
- Cleaning: date normalization, dedup by report number, device-family
  classification — every drop accounted for in a cleaning ledger.
- Analyses: monthly control charts (3σ), disproportionality signals
  (PRR/ROR + Evans rule), distinctive narrative vocabulary — each an
  engine in `R/`, each tested.
- Pipeline: config-driven stages with a test gate
  (`Rscript run_pipeline.R all`), executable Quarto report published
  to GitHub Pages.
- App (12 tabs): dashboard with click drill-downs; scoped ingest;
  pipeline runner with per-run **analysis scope**; read-only SQL
  console (two locks) with example picker; full data/figure/report
  export (CSV/Excel/JSON); run **ledger** with provenance line;
  **versioned result vintages** with a labeled run selector.
- 92 automated tests across 7 suites; every phase documented in
  `docs/` with figures, checkpoints, and a glossary.

**Verified**
- Full app-driven re-fetch of the entire dataset reproduced every
  raw file **byte-for-byte** and every downstream count to the digit.
- MAUDE observed revising narrative text in place (identical counts,
  37 vocabulary rows shifted across days) — recorded in the honesty
  notes.

**Known limitations (deliberate, documented)**
- Long stages block the browser (single R session); the full fetch
  belongs in the Terminal.
- Event tables are unversioned: drill-downs always query current
  events, even under an older vintage's charts.
- The report always renders the latest vintage.
- Signals/terms require ≥2 families in scope (comparative statistics
  need a comparison); single-family runs skip them with a log line.

**Roadmap** — see README § Roadmap: deployment (viewer/operator
split), background execution with live logs, versioned events,
rolling-baseline control limits, report vintage comparison,
Search-After for >26k slices, bigrams, manufacturer entity
resolution.
