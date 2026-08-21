[← README](../README.md) · [All docs in order](../README.md#the-tutorial-in-order) · [Glossary](GLOSSARY.md)

# 08 — Phase 7: The pipeline and the report — reproducibility, demonstrated

**Prerequisites:** Phases 1–6 complete and committed; the app working.
**Learning goal:** after this phase you will understand what a data
pipeline is, why configuration lives apart from code, why the test
suite runs as the pipeline's final gate, what an executable document
is, and what it takes to honestly claim "reproducible."
**Why this phase exists in a real workflow:** six phases of scripts
each work — but "rerun everything" currently means remembering an
order and running five things by hand. Real analytical systems are
rerun constantly (new data arrives monthly; MAUDE itself revises
past reports), so the rerun must be *one command, in the right
order, that proves itself at the end*. And stakeholders don't read
databases — they read reports. This phase delivers both, and in
doing so turns the README's oldest promise — same raw files in, same
results out — into something you can demonstrate on demand.

**The design rule this phase embodies (and Phase 8 will depend on):**
a capability that exists only inside a script — or behind a button —
can only be run by a human who remembers it. Wrapped as a *function
taking a config*, it can be run by anything: the runner, the tests, a
scheduler, next phase's app. **Runners and UIs wrap pipelines; they
never contain them.**

**Session plan:**
- **Session A (~1.5 h):** concepts + steps 4.1–4.3 (read the three
  new files, run single stages, then the full default pipeline).
- **Session B (~1 h):** steps 4.4–4.6 (render the report, publish it
  to Pages, tests) + commit.

---

## 1. Concepts, plainly

**A pipeline is an assembly line for data.** Raw material (API JSON)
enters one end; finished goods (tables, figures, a report) exit the
other; between them, *stages* — each doing one job, each handing its
output to the next. You have been running this assembly line by hand
since Phase 1: `fetch → load → clean → trend → signals → terms`.
Phase 7 doesn't change what the stages do — it makes the line
*runnable as a line*.

**Configuration is the settings panel; code is the machinery.** Every
tunable number — the four families, the Evans thresholds, the word
floor, the paths — now lives in ONE file, `pipeline/config.R`, read
by every stage. Change a threshold, rerun, done: no hunting through
scripts. The one deliberate exception is documented in the file
itself: the *fetch* scope lives in `ingest/fetch_maude.py`'s
CONFIGURATION block, next to the API code it drives.

**Each stage is a function; the runner just walks a list.**
`pipeline/stages.R` defines `stage_load()`, `stage_clean()`, …,
`stage_test()` — each takes the config, does one job, prints one
status line, returns a small summary. A *registry*
(`PIPELINE_STAGES`) maps names to functions in canonical order, and
`run_pipeline.R` is deliberately thin: decide which stages, run them
in order with timing, stop loudly on failure. Adding a stage later =
one function + one registry entry.

**The test suite is the final gate.** The default run *ends* by
executing all 50 tests; if any fails, the pipeline run FAILS. That's
the professional pattern: a pipeline that verifies its own math on
every run is one you can trust unattended — data can change under
you (MAUDE revises history!), and the gate catches what a human
wouldn't re-check.

![The pipeline](img/pipeline_diagram.png)

**Offline by default, fetch by name — and Phase 1 in full when you
want it.** `Rscript run_pipeline.R` runs
`load → clean → trend → signals → terms → test` — everything
downstream of the raw files, minutes not hours, no API key needed.
The full refresh, Phase 1 included, is a two-command flow:

```bash
Rscript run_pipeline.R probe    # ask the API what the fetch would get
Rscript run_pipeline.R all      # fetch -> load -> ... -> test
```

The probe is its own stage on purpose: **pipelines never ask
"continue? y/N" mid-run** — an unattended run can't answer — so the
look-before-you-leap decision lives *between* commands: probe, read
the counts, then commit to `all`. Two lessons in one split:
expensive, external, credentialed steps are opt-in; and human
judgment sits between pipeline runs, never inside them.

The pipeline can also **finish the job**: a `report` stage renders
the Quarto report against the current database and publishes it to
`docs/`. (The `.qmd` is source code — never regenerated; only its
rendered HTML is.) It runs in `all` or by name — not in the offline
default, because it needs the quarto binary and adds a minute:

```bash
Rscript run_pipeline.R report          # render + publish, one command
Rscript run_pipeline.R                 # then this stays the fast loop
```

**An executable document.** `report/orthowatch_report.qmd` is a
Quarto file: prose with embedded R chunks. *Rendering* it runs every
chunk against the database and weaves the results — numbers, tables,
figures — into one self-contained HTML file. Nothing is pasted, so
the report can never drift out of date from the data: re-render and
every number recomputes. (Quarto is the successor to R Markdown and
ships inside RStudio — the Render button just works.)

**The reproducibility ladder, honestly stated.** Same raw files →
same database (the loader rebuilds from scratch; cleaning is
deterministic) → same tables and figures (seeded, tested engines) →
same report (rendered from the database). The one rung outside our
control is the first: a fresh *fetch* may return different data,
because MAUDE itself revises. That's not a flaw in the pipeline —
it's why the pipeline records `source_file` on every row and keeps
raw files immutable.

## 2. Get the Phase 7 files into your repo

| File | Goes in | Job |
|---|---|---|
| `config.R` | `pipeline/` (new folder) | The settings panel |
| `stages.R` | `pipeline/` | Seven stage functions + the registry |
| `run_pipeline.R` | project **root** | The thin runner |
| `orthowatch_report.qmd` | `report/` — delete `report/.gitkeep` | The executable report |
| `test-pipeline.R` | `tests/testthat/` | Pins config, registry, one stage end-to-end (suite → 50) |
| `run_tests.R` | `tests/` (replaces) | Now sources the pipeline too |
| `pipeline_diagram.png` | `docs/img/` | The figure above |
| `make_illustrations.R` | `docs/img/` (replaces) | Now also generates it |

**Files-landed check** (validated):

```bash
ls pipeline/config.R pipeline/stages.R run_pipeline.R report/orthowatch_report.qmd
grep -c "PIPELINE_STAGES <- list" pipeline/stages.R      # expect 1
grep -c "DEFAULT_STAGES" pipeline/stages.R               # expect 1
grep -c 'source("pipeline/stages.R")' tests/run_tests.R  # expect 1
```

## 3. Run it, step by step

### 4.1 Read the three files, in order

`pipeline/config.R` (2 min — recognize every number: they're Phase
3–5's documented judgment calls, now in one place), then
`pipeline/stages.R` (10 min — notice each stage is your own analysis
script's core, condensed: same engines, same column selections, same
thresholds-from-config), then `run_pipeline.R` (2 min — notice how
little it does; that thinness is the design).

### 4.2 One stage alone

```bash
Rscript run_pipeline.R trend
```

**You should see:** the stage banner, then
`[trend] monthly_trends: 240 rows; 152 flagged`, then the timing
table. **What it means:** a single stage, runnable by name — the
exact numbers you know from Phase 3, now produced by the pipeline.
(That the pipeline's numbers match your hand-run scripts' numbers IS
the reproducibility claim, checked.)

### 4.2b The full-refresh flow (know the pattern; run it when you choose)

The pipeline can run Phase 1 end to end. First the free look:

```bash
Rscript run_pipeline.R probe
```

**You should see:** the fetch script's probe output — per-family,
per-year report counts and its estimate of the requests a real fetch
would make — and no files written. **What it means:** you know
exactly what `all` would download before spending half an hour and
your API quota on it.

Then, when you actually want fresh data (venv active,
`OPENFDA_API_KEY` exported, tens of minutes):

```bash
Rscript run_pipeline.R all
```

That is Phase 1 → Phase 5 → the test gate, one command. No need to
run it today — your raw files are current — but this is the monthly-
refresh move, and knowing it exists is the point. (Remember the
ladder's honest rung: a fresh fetch may change numbers, because
MAUDE itself revises history.)

### 4.3 The full default run

```bash
Rscript run_pipeline.R
```

**You should see** (your real numbers, ~2–4 minutes total, `terms`
the slow one):

```
== OrthoWatch pipeline ==  stages: load -> clean -> trend -> signals -> terms -> test
── stage: load ──
[load] raw_events: 84,549 rows
── stage: clean ──
[clean] clean_events: 84,547 rows (from 84,549 raw)
── stage: trend ──
[trend] monthly_trends: 240 rows; 152 flagged
── stage: signals ──
[signals] signal_stats: 312 pairs; 64 Evans signals
── stage: terms ──
[terms] narrative_terms: ... rows
── stage: test ──
[test] suite green
== pipeline complete ==
   stage seconds
```

**What it means:** the entire project, one command, self-verified at
the end. Every figure in `figures/` and every published chart in
`docs/interactive/` was just regenerated — `git diff` will show them
modified; that's *correct* (regenerated artifacts are the pipeline
working), and committing them is part of the ritual.

(The venv must be active for the `load` stage — it runs Python. FAQ
covers the error you get if it isn't.)

### 4.4 Render the report

Two equivalent ways — the button or the stage:
in RStudio, open `report/orthowatch_report.qmd` and click **Render**;
or in the Terminal, `Rscript run_pipeline.R report` (which renders
AND does 4.5's publish copy for you — it finds quarto even when your
terminal's PATH doesn't, by checking RStudio's bundled copy).

**You should see:** chunk-by-chunk progress, then
`Output created: orthowatch_report.html`, and the report opening —
title, your honest read-this-first, the family table, all three
analyses with your real figures and top-10 tables, and a closing
section explaining how it made itself.

### 4.5 Publish the report

The rendered HTML is self-contained — which means Pages can serve it
exactly like the charts:

```bash
cp report/orthowatch_report.html docs/orthowatch_report.html
```

After this phase's commit it will be live at
`https://akannan2987.github.io/orthowatch/orthowatch_report.html` —
the project's whole story, one URL. (The `report/` copy stays
gitignored as a build product; the `docs/` copy is the published
artifact — same preview-vs-published pattern as the charts.)

### 4.6 Tests

```bash
Rscript tests/run_tests.R
```

**You should see:** **five** contexts — `interactive_meta, pipeline,
signal_detection, text_mining, trending` — and
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 50 ]`. The eight new expectations
pin the config's shape, the registry's order and offline default,
the test-gate-comes-last rule, and one stage run end-to-end against
a temporary database.

## 5. Checkpoint

1. `Rscript run_pipeline.R trend` runs one stage and prints your
   Phase 3 numbers (4.2).
2. `Rscript run_pipeline.R` completes all six default stages green,
   ending in `[test] suite green` (4.3).
3. The report renders and reads correctly with your real numbers
   (4.4).
4. `docs/orthowatch_report.html` exists (4.5).
5. Suite: five contexts, 50 green (4.6).

## 6. Commit checkpoint

README edits (row 7 flip + gallery block + tree) — done for you this
phase; verify with:
`grep -c "docs/08-phase-7-pipeline-report.md" README.md` → 1.

```bash
git add .
git status   # expect: pipeline/ (2), run_pipeline.R, report .qmd,
             # docs/orthowatch_report.html, test-pipeline.R, run_tests.R,
             # doc 08, both img files, GLOSSARY, README — plus regenerated
             # figures/*.png and docs/interactive/*.html (correct!);
             # no data/, no report/*.html
git commit -m "Phase 7: config-driven pipeline (one command, test-gated) + Quarto report rendered from the db and published; tests to 50"
git push origin develop develop:beta develop:master
```

Then Actions → green → the report URL loads.

## 7. What could go wrong (mini-FAQ)

**`load failed ... venv activated?`** — the load stage runs Python;
activate the venv first (`source .venv/bin/activate`) in the same
terminal, then rerun. (The R stages don't care; only fetch/load do.)

**`quarto: command not found` in the Terminal** — use RStudio's
Render button instead (RStudio bundles Quarto). Adding the CLI to
your PATH is optional polish, not required.

**The `terms` stage is slow / RAM spikes** — expected: it re-tokenizes
12M words. Minutes, not seconds; close other heavy apps if tight.

**`git status` shows every figure and published chart modified after
a run** — correct and by design: the pipeline regenerates them.
Commit them; that's the artifacts staying in sync with the data.

**`database is locked`** — the app or an RStudio session holds the
db; stop the app / close connections, rerun.

**`unknown stage(s): ...`** — typo in a stage name; the error lists
the known ones. Order doesn't matter — the runner enforces canonical
order itself.

**Should I delete `data/raw` to prove the fetch works?** — No.
`data/` is gitignored, so Git cannot restore it — and a re-fetch
will NOT return identical data, because MAUDE revises history. Your
raw files are the frozen snapshot behind every committed number;
deleting them to test the fetch is testing the parachute by
throwing away the spare. The `probe` stage already proves the API
plumbing (same endpoint, auth, and queries — real requests, nothing
saved). For a genuine full-refresh drill, back up instead of
deleting (`mv data/raw data/raw_snapshot_YYYY-MM`), run
`Rscript run_pipeline.R all`, compare fetch logs and counts, then
decide which snapshot to keep — and expect regenerated artifacts to
shift and be recommitted, which is the pipeline doing its job.

**A fresh `fetch` changed my numbers** — not a bug: MAUDE revises
past reports. That's the ladder's first rung being outside our
control — and why raw files + `source_file` traceability exist.

## 8. Two ways to run everything — the table, complete

| Capability | Manual path (learn) | Pipeline path (rerun) |
|---|---|---|
| Probe the API | `python ingest/fetch_maude.py --probe` | `Rscript run_pipeline.R probe` |
| Fetch raw | `python ingest/fetch_maude.py` | `Rscript run_pipeline.R all` |
| Load | `python ingest/load_to_sqlite.py` | stage `load` |
| Clean | `analysis/01_clean_events.R` | stage `clean` |
| Trend | `analysis/02_trending.R` | stage `trend` |
| Signals | `analysis/03_signal_detection.R` | stage `signals` |
| Narratives | `analysis/04_text_mining.R` | stage `terms` |
| Verify | `Rscript tests/run_tests.R` | stage `test` (the gate) |
| Tell the story | RStudio Render button | `Rscript run_pipeline.R report` (renders + publishes) |

The analysis scripts remain the *learning* path — walkable line by
line, with the missions and verdicts. The pipeline is the *rerun*
path. Same engines underneath: one engine, many consumers, now
including a machine.

---

**Next:** `09-phase-8-mission-control.md` — the app grows from
dashboard to workbench: a Pipeline tab (run stages from the browser,
scoped, with progress), a read-only Query console, and a Report tab —
every button wrapping the stage functions built here. The API this
phase created is the reason that phase will be assembly, not
construction.
