[← README](../README.md) · [All docs in order](../README.md#the-tutorial-in-order) · [Glossary](GLOSSARY.md)

# 02 — Phase 1: Ingestion — real FDA data lands on your laptop

**Prerequisites:** `01-setup.md` completed (all 8 verification checks pass,
first commit pushed).
**Learning goal:** after this phase you will understand what an API is by
having used one, what JSON is by having read some, why pagination, rate
limits, and API keys exist, and how data gets from a public web service
into a SQL database — with a provenance trail.
**Why this phase exists in a real workflow:** every surveillance analysis
begins with getting data *reliably and traceably*. Teams that fetch data
ad hoc (download a file, rename it, forget where it came from) cannot
answer an auditor's first question: "where did this number come from?"
Our ingestion leaves a paper trail by design.

**Session plan:**
- **Session A (~1.5–2 h):** concepts + explore the API in your browser +
  API key setup + probe + full fetch (steps 1–6).
- **Session B (~1–1.5 h):** load into SQLite + verify from R + commit
  (steps 7–10).

---

## 1. Four concepts, plainly

**API (Application Programming Interface).** A website designed for
programs instead of people. You request a specific URL; instead of a
styled page, you get raw data back. The FDA runs one at
`https://api.fda.gov` serving its public datasets.

**JSON.** The format the data arrives in — nested labeled lists, readable
by humans and machines alike:

```json
{"report_number": "1234567-2023-00042",
 "event_type": "Malfunction",
 "device": [{"generic_name": "PROSTHESIS, HIP, SEMI-CONSTRAINED"}]}
```

Curly braces = an object (labeled fields), square brackets = a list.
That's 90% of JSON. Note the comma-inverted device name — FDA writes
"PROSTHESIS, HIP", not "hip prosthesis". This detail matters in step 2.

**Pagination.** The API won't hand you 50,000 reports in one response —
you get pages (max 1,000 records each) and step through them with a
`skip` parameter: skip 0, skip 1000, skip 2000... like reading a book
1,000 words at a time. openFDA stops this walk at ~26,000 results per
query, which is why our fetcher slices requests by device family **and**
year — each slice stays under (or near) the ceiling.

**Rate limits and API keys.** openFDA allows 240 requests/minute; without
a key you also get only 1,000 requests/day per IP address, and — more
importantly — anonymous script traffic is sometimes blocked outright by
the API's bot-detection layer (HTTP 403). A free API key identifies you
as a legitimate caller, raises the daily allowance to 120,000, and makes
403s rare. Getting and safely storing a key is part of this phase.

## 2. Touch the API with your bare hands (browser, no code)

Before any script, see the thing itself.

1. Paste this into your browser's address bar:

```
https://api.fda.gov/device/event.json?search=device.generic_name:(hip AND prosthesis)&limit=1
```

(Your browser converts spaces and parentheses to `%20`, `%28`, `%29` —
that's URL encoding, done for you.)

2. You'll see a JSON wall. Find these landmarks:
   - `"meta"` → `"results"` → `"total"` — how many reports match your
     search **in total**. You just measured the size of a real
     surveillance problem in one browser call.
   - `"results"` — a list containing the 1 report you asked for
     (`limit=1`). Skim it: dates, an `event_type`, a `device` list, an
     `mdr_text` narrative. This is the raw material of the whole project.

3. Now a lesson this project learned the hard way. Try the same search
   as an exact phrase:

```
https://api.fda.gov/device/event.json?search=device.generic_name:"hip prosthesis"&limit=1
```

   Compare the two `total` values. The phrase version finds a tiny
   fraction — because `"..."` matches words *in that order*, and FDA
   generic names are comma-inverted (`PROSTHESIS, HIP, ...`). The
   `(hip AND prosthesis)` version requires both words in *any* order and
   matches properly. **Moral: before trusting a search, check how the
   source encodes the thing you're searching for.** Our first fetcher
   used phrase queries; implausibly low probe counts (45 hip reports in
   a year) exposed the bug before we downloaded the wrong dataset.

> A quirk to remember: when a search matches **zero** reports, openFDA
> returns a "404 Not Found" error instead of an empty list. Our script
> knows this; don't let it scare you in the browser either.

## 3. Get a free API key and store it safely

1. Go to <https://open.fda.gov/apis/authentication/>, enter your email,
   and copy the key you receive.
2. The key must be available to the script but must NEVER appear in your
   code or your Git history. The standard pattern: an **environment
   variable** — a named value attached to your terminal session that
   programs can read at runtime. The script asks for it by name
   (`OPENFDA_API_KEY`); the value lives only on your machine.
3. To set it permanently, add one line to your shell's startup file —
   the file your terminal reads every time it opens. Which file depends
   on your shell (`echo $SHELL` tells you):

   | Your shell | Startup file | Add the line with |
   |---|---|---|
   | `/bin/zsh` (macOS default) | `~/.zshrc` | `echo 'export OPENFDA_API_KEY="your-key"' >> ~/.zshrc` |
   | `/bin/bash` (older Macs, Linux) | `~/.bash_profile` (macOS) or `~/.bashrc` (Linux) | `echo 'export OPENFDA_API_KEY="your-key"' >> ~/.bash_profile` |
   | Windows (Command Prompt) | (registry, handled for you) | `setx OPENFDA_API_KEY "your-key"` then open a NEW terminal |

4. Load it into the current session (`source ~/.bash_profile` or
   `source ~/.zshrc`, or open a new terminal) and verify:

```bash
echo $OPENFDA_API_KEY      # expected: your key printed back
```

5. **Also give the key to R** (this matters from Phase 7 onward, and
   it's a subtle, important lesson): an environment variable is
   inherited *at process birth, from the parent* — and from nowhere
   else. Your shell startup file covers every program launched **from
   a Terminal** (the fetch script, `Rscript run_pipeline.R`), but
   RStudio launched from the Dock is born of a *different* parent and
   never sees your Terminal's export — so neither does anything R
   starts, including the app's fetch buttons. R has its own startup
   file for exactly this: **`.Renviron`** in the project root, read
   at every R session start. Set it up now (paste your real key):

```bash
# In the project root:
echo 'OPENFDA_API_KEY=your-key-here' >> .Renviron

# CRITICAL — a secret must never enter Git. The project's .gitignore
# already ignores .Renviron; verify the shield is up:
git check-ignore -v .Renviron    # expected: .gitignore:<line>  .Renviron
```

   Then restart R (Session → Restart R — startup files are read at
   birth) and verify from the R Console:

```r
nchar(Sys.getenv("OPENFDA_API_KEY")) > 0    # expected: TRUE
```

   Two homes, one key: the shell startup file for Terminal-launched
   programs, `.Renviron` for R and everything R launches. (Note the
   `.Renviron` line has **no `export` and no quotes** — R's format,
   not the shell's.)

6. Why none of this can leak to GitHub: the shell startup file lives
   in your home folder, *outside* the repo — Git cannot commit what it
   cannot see — and the in-repo `.Renviron` is gitignored. The
   one remaining risk is human: never paste the key into a script, doc,
   commit message, or screenshot. If a key ever does leak, delete it on
   the openFDA site and generate a new one — keys are disposable.

## 4. Get the Phase 1 files into your repo

| File | Goes in | Job |
|---|---|---|
| `fetch_maude.py` | `ingest/` | API → raw JSON files |
| `load_to_sqlite.py` | `ingest/` | raw JSON → SQLite table |
| `00_verify_ingest.R` | `analysis/` | prove R can read the result |

**Files-landed check** (the habit from setup §12b — `ls` screams
`No such file` for anything missing):

```bash
ls ingest/fetch_maude.py ingest/load_to_sqlite.py analysis/00_verify_ingest.R
```

Open `fetch_maude.py` in RStudio and **read the configuration block** at
the top before running anything. Knowing what a script will do before
running it is a professional reflex worth building on day one. The four
device queries cover major orthopedic device families: joint
reconstruction (hip, knee), trauma fixation (bone plates), and spinal
fixation. The script's header also records
its own v1→v2 history — the query fix and the 403 handling — because a
repo that shows its corrections teaches more than one that hides them.

## 5. Probe before you fetch

In the Terminal (venv active — you'll see `(.venv)` in the prompt;
if not: `source .venv/bin/activate`):

```bash
python ingest/fetch_maude.py --probe
```

Expected output shape (your numbers WILL differ — MAUDE updates weekly):

```
slice                        reports available
----------------------------------------------
hip_prosthesis 2020                     xx,xxx
...
spinal_fixation 2024                     x,xxx
----------------------------------------------
TOTAL                                  xxx,xxx

Estimated download requests: ~xxx (daily allowance: 120,000 (with key))
```

Read the table before fetching — the probe exists to catch problems
while they're still free:

- **Implausibly small counts** for a device family you know is common →
  your search probably doesn't match how the source spells things
  (see step 2.3).
- **`⚠ over paging ceiling` flags** → that slice has more than ~26,000
  reports; the fetch will take the first ~26,000 and record the
  truncation honestly in the log.
- **The request estimate** → sanity-check it against your daily
  allowance (huge with a key; 1,000 without).

## 6. Fetch for real

```bash
python ingest/fetch_maude.py
```

Expected: a progress line per slice; a few minutes to tens of minutes
depending on the total (the 1-second politeness pause dominates):

```
[hip_prosthesis 2020] page  19 saved (18,423/18,423 reports)
...
Done. Raw files in data/raw/ — log written to data/raw/fetch_log.csv
```

Lines like `… got HTTP 403; retrying in 5s` are the retry mechanism
working, not failing — the script waits and knocks again. It only stops
if a request fails all retry attempts.

Then look at what arrived:

```bash
ls data/raw | head                    # the page files
head -c 500 data/raw/fetch_log.csv    # the traceability log
```

Open `fetch_log.csv` (RStudio can view it): one row per slice — what was
asked, when, how many existed, how many were fetched, and whether the
slice was complete or truncated. **This file is your answer to "where
did this data come from?"** — the principle is *traceability by design*.

> These files are gitignored (recall why from setup: data is regenerated
> by scripts; the repo proves the pipeline works precisely because the
> data is *not* checked in).

## 7. Load into SQLite

```bash
python ingest/load_to_sqlite.py
```

Expected ending:

```
──── load summary ────
rows written to raw_events : xxx,xxx
unique report_number values: xxx,xxx
date_received range        : 20200101 → 20241231
event_type counts:
Malfunction    ...
...
Database written to data/processed/orthowatch.db
```

Read the script afterwards — its docstring explains the two design
decisions worth internalizing: **flattening** (nested reports become one
row each, first device kept, simplification stated out loud) and
**rebuild-from-scratch loading** (rerunning always gives the same table
from the same raw files — reproducibility as a habit, not a slogan).

## 8. Checkpoint: verify from R (the handoff moment)

Open `analysis/00_verify_ingest.R` in RStudio and run it **line by line**
(cursor on a line, `Cmd/Ctrl+Enter`). This is the project's first
cross-language handoff: Python fetched and loaded; R now reads the same
database. Every serious data team has a seam like this somewhere.

For every query, here is what you should see (numbers from one real
August 2026 download — yours will differ slightly in size, never in
shape) and what it means:

**Query 1 — what tables exist:**

```
[1] "raw_events"
```

The cabinet holds exactly one table so far; Phase 2 adds the second.

**Query 2 — how many rows:**

```
  n_rows
1  84549
```

Must equal the loader's "rows written" figure exactly — same database,
same count, two languages.

**Query 3 — first five rows:** five real report forms, e.g.

```
          report_number date_received  event_type          generic_name
1    8030965-2020-00001      20200102      Injury   PLATE,FIXATION,BONE
2    2939274-2020-00013      20200102      Injury PLATE, FIXATION, BONE
...
```

Note `date_received` is still an eight-digit *text string*, not a real
date — and rows 1–2 already show the same device spelled with and
without spaces. Both facts are Phase 2's to fix.

**Query 4 — the top device names:** FDA-style comma-inverted names
(`PROSTHESIS, KNEE` ~10.9k, `PROSTHESIS, HIP` ~10.6k, ...) including
near-duplicate variants (`PLATE, FIXATION, BONE` *and* `PLATE, BONE`)
and even a name cut off mid-word by the source (`..., POROUS, CO`).
**This mess is next phase's raw material** — screenshot it; it's the
"before" picture for your README.

**Query 5 — reports per year:** all five fetched years, tens of
thousands each, e.g.

```
  year     n
1 2020 20543
2 2021 18243
3 2022 15151
4 2023 13755
5 2024 16857
```

Counts moving year to year is normal — and resist reading meaning into
the movement yet: reporting volume is not incidence (see the honesty
notes in the README). Phase 3 treats trends properly.

The checkpoint passes when all five outputs match in shape, and query
2 matches your loader summary exactly.

## 9. Same task, different language (optional, 15 min)

This project deliberately uses both R and Python. Here's the API call
from step 2, in R — run it in the Console if curious:

```r
library(httr2)   # install.packages("httr2") first; renv::snapshot() after

resp <- request("https://api.fda.gov/device/event.json") |>
  req_url_query(
    search = 'device.generic_name:(hip AND prosthesis)',
    limit  = 1
  ) |>
  req_perform()

body <- resp_body_json(resp)
body$meta$results$total     # same number you saw in the browser
```

Trade-offs, honestly: R's httr2 is every bit as capable for API work.
We used Python for ingestion because (a) in industry, ingestion is more
often owned by Python; (b) a clean Python→SQL→R seam mirrors how real
data teams hand work across specialties; and (c) it keeps each language
doing what it is best known for. Being able to *justify* a language choice
matters more than the choice.

## 10. Commit checkpoint

```bash
git add .
git commit -m "Phase 1: ingest MAUDE orthopedic reports via openFDA API into SQLite"
git push
```

`git status` before committing should show only code and docs — no
`data/` files (the .gitignore at work) and no API key anywhere.

**Phase 1 complete.** You've pulled a large slice of real FDA adverse
event reports through an authenticated public API into a queryable
database, with a provenance log — the first mile of a real post-market
surveillance system.

## 11. What could go wrong (mini-FAQ)

**`ModuleNotFoundError: No module named 'requests'`** — venv not active
in this terminal. `source .venv/bin/activate`, retry.

**HTTP 403 Forbidden during fetch (even though --probe worked)** —
api.fda.gov sits behind bot-detection (an edge-security layer) that can
block anonymous script traffic, sometimes only for larger requests. The
script's three-part fix: an identifying User-Agent header, a free API
key (step 3), and retry-with-backoff. If 403s persist through all
retries, verify the key is really set (`echo $OPENFDA_API_KEY`) in the
SAME terminal you're running the script from. Real-world lesson: public
APIs have security in front of them; identify and authenticate yourself.

**Probe counts look implausibly low for a common device** — your search
doesn't match how the source encodes names. FDA generic names are
comma-inverted ("PROSTHESIS, HIP"), so exact-phrase searches miss them;
AND-style term searches (`(hip AND prosthesis)`) don't. Check the
encoding before trusting the count (step 2.3).

**`TypeError: ... expected str instance, NoneType found` while loading**
— a list field inside a report contains a null entry (yes, really —
e.g. `product_problems = ["Fracture", None]`). The loader's
`join_clean()` helper filters these out before joining. General lesson:
real-world JSON lists can contain nulls; filter before you join.

**`Network error: could not reach api.fda.gov`** — no internet, or a
corporate proxy is interfering. Try the browser URL from step 2; if the
browser works but the script doesn't, you're behind a proxy — run from a
personal network.

**Browser shows `NOT_FOUND` / script logs a slice as `empty`** — that
search matched zero reports. In the browser: check the syntax. In the
script: normal for some slices; the log records it.

**HTTP 429 error** — rate limit exceeded. Nearly impossible with the
built-in sleep; the retry logic waits it out automatically.

**Fetch interrupted midway** — just rerun `fetch_maude.py`. It refetches
everything (minutes); the loader rebuilds the table from whatever raw
files exist. Idempotence — safe to rerun — is a design feature.

**A slice flagged `truncated_at_ceiling`** — that device/year had more
than ~26,000 reports; skip/limit paging can't reach the rest. The log
records available vs. fetched. The professional fix (openFDA's
Search-After feature or bulk downloads) is on the roadmap — and
documenting the trade-off openly is part of doing this properly.

**`database is locked` when loading** — the DB is open elsewhere (often
a forgotten R connection from step 8). Disconnect and rerun.

## 12. Two ways to run everything (running tally)

| Capability | Manual path (now) | Automatic path (later) |
|---|---|---|
| Fetch data | `python ingest/fetch_maude.py` | Phase 7's one-command pipeline runs fetch → load → analyze → render |
| Load to DB | `python ingest/load_to_sqlite.py` | same |
| Inspect data | `00_verify_ingest.R` line by line | the Shiny dashboard (Phase 6) |

---

**Next:** `03-phase-2-cleaning.md` — the messiest, most instructive phase:
turning raw MAUDE chaos into an analysis-ready table, one visible fix at
a time.
