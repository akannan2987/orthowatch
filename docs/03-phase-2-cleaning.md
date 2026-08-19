# 03 — Phase 2: Cleaning & harmonization — from chaos to analysis-ready

**Prerequisites:** Phase 1 complete — `raw_events` exists in
`data/processed/orthowatch.db` and the Phase 1 checkpoint queries ran.
**Learning goal:** after this phase you will understand R's tidyverse
verbs (`mutate`, `filter`, `count`, the `|>` pipe), what NA means and why
missing data deserves explicit handling, the difference between reusable
functions and runnable scripts, a first taste of regular expressions, and
the single most important cleaning principle: *never modify your raw data
— derive from it, visibly.*
**Why this phase exists in a real workflow:** raw surveillance data
cannot be analyzed directly. The same device is spelled five ways
(`PLATE, BONE` / `PLATE,FIXATION,BONE` / `PLATE, FIXATION, BONE`), dates
are strings, some records are blank where it matters, and some are
duplicates. Every conclusion downstream inherits the quality of this
step — which is why cleaning is done as documented, inspectable code,
not ad-hoc edits.

**How this guide works:** section 4 walks the analysis script
step by step. After every step you'll find **"You should see"** — a
sample of the expected output — and **"What it means"**. The sample
numbers come from one real download (August 2026); MAUDE updates
weekly, so yours will differ slightly. The *shape* should match; the
guide flags which differences are fine and which are warning signs.

**Session plan:**
- **Session A (~1.5 h):** concepts + read the engine + run steps
  4.1–4.5.
- **Session B (~1–1.5 h):** steps 4.6–4.10, tune rules if needed,
  commit.

---

## 1. Concepts, plainly

**Two places data lives — the desk and the filing cabinet.** This is the
concept everything else in this phase stands on. The **database file**
(`data/processed/orthowatch.db`) is a filing cabinet on your disk:
tables stored in it are permanent — restart your computer, they're
still there. Your **R session** is a desk: objects you create (`raw`,
`clean`, ...) live in temporary memory, appear in RStudio's Environment
pane, and are wiped whenever R restarts. The Environment pane shows
ONLY the desk — database tables never appear there; you check the
cabinet by *asking* it: `dbListTables(con)`.

The whole phase is one round trip between the two:

```
      CABINET (disk, permanent)            DESK (R session, temporary)

  ┌───────────────┐  dbReadTable()   ┌──────────────┐
  │  raw_events   │ ───────────────▶ │     raw      │ photocopy of raw
  └───────────────┘                  └──────┬───────┘
                                            │ clean_events(raw)
                                            ▼
                                     ┌──────────────┐
                                     │    clean     │ cleaned copy
                                     └──────┬───────┘
                                            │ select(...)
                                            ▼
  ┌───────────────┐  dbWriteTable()  ┌──────────────┐
  │ clean_events  │ ◀─────────────── │ clean_for_db │ trimmed copy
  │  (NEW table)  │                  └──────────────┘
  └───────────────┘
```

`dbReadTable()` photocopies a cabinet table onto the desk. All cleaning
happens to desk copies. `dbWriteTable()` files the finished copy back
into the cabinet under a new label. The desk objects are scaffolding —
they exist to build `clean_events` and are *supposed* to vanish on
restart. The phase's real deliverable is the cabinet's new table.

**The pipe (`|>`).** R's way of chaining steps left-to-right:
`data |> step1() |> step2()` reads "take data, do step1, then step2".
Think of an assembly line. (You'll also see `%>%` in older code — same
idea, older syntax.)

**`mutate()`** adds or changes columns. **`filter()`** keeps rows
matching a condition. **`count()`** tallies rows per group. These three
verbs plus the pipe cover most everyday data work.

**NA** is R's "value missing" marker. The discipline that matters:
missing data is *information* ("this report didn't say") and gets
handled explicitly — counted, labeled `"Unknown"`, or set aside —
never silently dropped.

**Functions vs. scripts.** A *script* (in `analysis/`) is a narrative
you run top to bottom. A *function* (in `R/`) is a reusable tool that
scripts, the dashboard, the report, and tests can all call. Phase 2
introduces this split, and every later phase relies on it: one cleaning
logic, used everywhere, tested once.

**Regular expressions (regex), the 2% you need today.** A regex is a
pattern language for text. We use exactly one non-obvious piece:
`",\\s*"` means "a comma followed by any amount of whitespace" — which
lets one rule normalize `PLATE,FIXATION` and `PLATE,  FIXATION` alike.
`str_detect(x, "HIP")` — "does the text contain HIP?" — is regex at its
gentlest.

**SQLite has no date type** — a genuine gotcha. We store dates as
ISO-8601 text (`"2023-04-15"`), which sorts and compares correctly as
plain strings. That's the standard trick, and it's why the clean table
carries `date_received_iso` and `year_month` columns.

## 2. Get the Phase 2 files into your repo

| File | Goes in | Job |
|---|---|---|
| `clean_events.R` | `R/` | The engine: reusable cleaning functions |
| `01_clean_events.R` | `analysis/` | The narrative: investigate → clean → inspect → write |

**Files-landed check:**

```bash
ls R/clean_events.R analysis/01_clean_events.R
```

No new packages needed — `dplyr`, `stringr`, `lubridate`, and `tibble`
all arrived with tidyverse in setup.

**Read `R/clean_events.R` before running anything** — top to bottom,
comments included; it's written to be read. Notice the shape: five small
functions, each doing one job and explaining itself, and one
orchestrator (`clean_events()`) that runs them in a fixed order and
prints a **cleaning ledger** — row counts announced at every step, so
no change to the data ever happens silently.

## 3. The cleaning rules, in English

1. **Dates:** parse `"20230415"` strings into real dates; unparseable
   ones become NA and are *counted*. Derive `date_received_iso` and
   `year_month` (the trending unit).
2. **Names:** normalize formatting only — uppercase, collapse stray
   whitespace, one space after commas, drop slashes (so
   `PATELLO/FEMOROTIBIAL` and `PATELLOFEMOROTIBIAL` unify). Formatting
   fixes are safe; rewriting *words* could merge genuinely different
   devices, so we don't.
3. **Family mapping — the heart of the phase:** every report gets a
   `device_family` (Hip prosthesis / Knee prosthesis / Bone plate /
   Spinal fixation / Other / Unknown) via readable contains-rules.
4. **Event types:** blanks and NAs become an explicit `"Unknown"`.
5. **Duplicates:** one row per `report_number`, keeping the most
   recently received version; rows with a *missing* report number are
   set aside first (a `distinct()` trap explained in the code) so they
   survive.

What we deliberately do **not** do (documented honesty): merge reports
describing the same real-world event filed by different reporters.
That's true entity resolution — a known hard problem in vigilance —
and it's on the roadmap, not swept under the rug.

## 4. Run the script, step by step — with expected output every time

Open `analysis/01_clean_events.R`. Run each chunk with the cursor on
it (`Cmd/Ctrl+Enter`), then compare against the samples below.

### 4.1 Load libraries, source the engine, connect

```r
library(DBI); library(RSQLite); library(dplyr); library(tibble)
source("R/clean_events.R")
con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")
```

**You should see:** nothing, or quiet package startup notes. Silence is
success. In the Environment pane, a `con` object appears — that's the
open phone line to the cabinet. `source()` also fills the Environment's
*Functions* section with the engine's functions (`clean_events`,
`classify_device_family`, ...).

**If instead:** `could not find function` errors later → this chunk was
skipped, or your working directory isn't the project root (`getwd()`
to check; open the `.Rproj` file to fix).

### 4.2 Read the raw table onto the desk

```r
raw <- dbReadTable(con, "raw_events") |> as_tibble()
nrow(raw)
```

**You should see:**

```
[1] 84549
```

**What it means:** `raw` is now a desk copy of the cabinet's raw table:
one row per downloaded report form. Your number must equal the "rows
written" figure from your Phase 1 load summary — if it doesn't,
something changed the database since; re-run the loader.

### 4.3 Investigate quirk #1: duplicated report numbers

```r
dbGetQuery(con, "
  SELECT report_number, COUNT(*) AS n
  FROM raw_events
  GROUP BY report_number
  HAVING n > 1
")
```

**You should see** (a very short table — your IDs will differ):

```
      report_number n
1 1234567-2023-00042 2
2 7654321-2024-00107 2
```

**What it means:** exactly which forms appear twice. `HAVING` filters
*groups* the way `WHERE` filters rows — its debut here. Now pull one up
in full and read both rows side by side:

```r
raw |> filter(report_number == "PASTE-ONE-ID-HERE") |> glimpse()
```

`glimpse()` prints every column vertically — ideal for comparing two
rows. Typical finding: the two rows are near-identical with a later
`date_received` on one — a follow-up version of the same form. That's
exactly what the dedup rule (keep newest) is for.

### 4.4 Investigate quirk #2: the event_type mess

```r
raw |> count(event_type) |> arrange(n)
```

**You should see** (shape and rough proportions):

```
# A tibble: 6 × 2
  event_type      n
  <chr>       <int>
1 ""              5
2 Other          11
3 Death         129
4 Malfunction 22124
5 Injury      62280
6 NA             NA?    <- you may see an NA row instead of/alongside ""
```

**What it means:** two different kinds of "missing" exist in the wild —
empty text (`""`) and true NA — plus note that `Other` here is the
**FDA's own category** on the form (11 reports), which is different
from the `Other` *device family* we create later. The cleaner will fold
both kinds of missing into one explicit `"Unknown"`.

### 4.5 Investigate quirk #3: how big is the name chaos?

```r
n_distinct(raw$generic_name)
```

**You should see:** a three-digit number, e.g.

```
[1] 6xx
```

**What it means:** several hundred distinct raw spellings are about to
be collapsed into a handful of families. That number is the size of
the problem this phase solves — remember it for the commit message.

### 4.6 Clean — one call, watch the ledger

```r
clean <- clean_events(raw)
```

**You should see** the ledger print as *messages* (red-ish text in
RStudio — that's normal, messages aren't errors):

```
raw input                                        84,549 rows
after parsing + standardizing                    84,549 rows
after deduplication                              84,547 rows
unparseable date_received (kept, NA)                  0 rows
device_family counts:
    device_family     n
1 Knee prosthesis 338xx
2  Hip prosthesis 307xx
3      Bone plate 111xx
4 Spinal fixation  88xx
```

**What it means, line by line:** parsing/standardizing *adds columns*
but never removes rows (both lines show the same count — a built-in
audit). Deduplication removed exactly the duplicates found in 4.3
(84,549 − 2 = 84,547 here; your arithmetic must work out the same way
with your numbers — if more rows vanished than duplicates found,
stop and investigate). Zero-or-few unparseable dates is normal.

**About the family counts — and where "Other" went.** `Other` is the
*leftover bin*: the label a report gets when its device name matches
none of the four family rules (the checklist's last line, `TRUE ~
"Other"`, means "nothing above matched"). You'll likely see it tiny or
missing entirely, and here's why, with a shopping analogy: if you buy
only apples, bananas, and oranges at the market, then sort your bag
into baskets labeled apples / bananas / oranges / *other fruit*, the
last basket stays empty — not because the sorting is clever, but
because you controlled what went into the bag. Same here: the Phase 1
download only requested reports whose device names contain the family
keywords (hip+prosthesis, etc.), and the classifier looks for those
same keywords — so nearly every report is guaranteed a match. The
empty basket still matters, twice over: (1) if the downloads ever
widen (more device types, looser searches), unmatched names will land
*visibly* in Other instead of being silently mislabeled — that's what
step 4.8 is for; (2) it's a tripwire today — a *large* Other with our
narrow download means something changed underneath us. In practice a
*handful* of Other rows does appear (10 in the reference run: bone
screws, bone cement, a wire passer), and the mechanism is worth
knowing: the FDA search matches *any* device listed on a report, but
our Phase 1 loader keeps only the *first* listed device. A report can
be fetched because its second device was a bone plate, yet flattened
to its first device — a screw. Those rows are the loader's documented
flattening simplification made visible (check `n_devices_on_report`
on them), not a bug. If Other is absent, the counts table simply
shows 4 rows; a large Other is the only alarming outcome. (And don't
confuse this with `event_type = "Other"` — that one is the FDA's own
tick-box for what *kind* of bad event occurred; same word, unrelated
column.)

### 4.7 Spot-check the family mapping

```r
clean |>
  count(device_family, generic_name_std, sort = TRUE) |>
  group_by(device_family) |>
  slice_head(n = 3) |>
  ungroup()
```

**You should see** (three sample names per family — sanity, not
completeness):

```
# A tibble: ~12 × 3
   device_family   generic_name_std                                        n
 1 Knee prosthesis PROSTHESIS, KNEE                                    108xx
 2 Knee prosthesis PROSTHESIS, KNEE, PATELLOFEMOROTIBIAL, SEMI-CONS…    8xxx
 3 Knee prosthesis PROSTHESIS, KNEE, FEMOROTIBIAL, SEMI-CONSTRAINED…    2xxx
 4 Hip prosthesis  PROSTHESIS, HIP                                     105xx
 ...
```

**What it means:** read the names against their assigned family — do
any look absurd (a knee filed under hips)? Also notice the slash
variants have merged: `PATELLO/FEMOROTIBIAL` no longer exists
separately. That's `standardize_generic_name()` visibly working.

### 4.8 If an Other bucket exists, read it

```r
clean |>
  filter(device_family == "Other") |>
  count(generic_name_std, sort = TRUE) |>
  print(n = 25)
```

**You should see:** either

```
# A tibble: 0 × 2
```

(empty — expected with the current download, see 4.6) or a short list
of names. If names appear, three verdicts are possible, and this is a
human judgment, not a code decision: genuinely other devices (screws,
cement — fine, leave them); obvious family members the rules missed
(add a case to `classify_device_family()` in `R/clean_events.R`,
re-run from 4.6, watch the bucket shrink — and note the change in a
comment beside the rule); or a large mysterious bucket (>5% of rows —
stop and investigate before continuing).

### 4.9 Date and event-type sanity

```r
range(clean$date_received_parsed, na.rm = TRUE)
clean |> count(event_type_clean, sort = TRUE)
```

**You should see:**

```
[1] "2020-01-01" "2024-12-31"

# A tibble: 5 × 2
  event_type_clean     n
1 Injury           622xx
2 Malfunction      221xx
3 Death              129
4 Other               11
5 Unknown              5
```

**What it means:** the parsed dates span exactly the window Phase 1
fetched — nothing leaked in from outside it. And the two kinds of
missing from 4.4 are now one honest `Unknown`; every category is
visible, nothing was dropped.

### 4.10 File the result into the cabinet

```r
clean_for_db <- clean |>
  select(report_number, mdr_report_key, date_received_iso, year_month,
         event_type = event_type_clean, device_family, generic_name_std,
         brand_name, manufacturer = manufacturer_std, model_number,
         n_devices_on_report, product_problems, narrative, source_file)

dbWriteTable(con, "clean_events", clean_for_db, overwrite = TRUE)
dbListTables(con)
```

**You should see:**

```
[1] "clean_events" "raw_events"
```

**What it means:** the cabinet now holds both tables — untouched
evidence and analysis-ready copy. Note what did NOT happen: nothing
new appeared in the Environment pane, because that pane only shows the
desk. `dbListTables()` is how you see the cabinet.

Then the closing query — the literal seed of Phase 3's trending:

```r
dbGetQuery(con, "
  SELECT device_family, year_month, COUNT(*) AS n_reports
  FROM clean_events
  GROUP BY device_family, year_month
  ORDER BY device_family, year_month
") |> head(10)

dbDisconnect(con)
```

**You should see** (one row per family per month):

```
   device_family year_month n_reports
1     Bone plate    2020-01       2xx
2     Bone plate    2020-02       2xx
3     Bone plate    2020-03       1xx
...
```

**What it means:** monthly report counts per device family — exactly
the series Phase 3 will chart and put control limits around.

## 5. Checkpoint

All of these must be true (each was verified inline above):

1. `dbListTables(con)` shows **both** `raw_events` and `clean_events`
   (4.10).
2. Ledger arithmetic closes: rows out = rows in − duplicates found
   (4.3 vs 4.6). Nothing else vanished.
3. You personally read the family spot-check (4.7) and the Other
   bucket, if any (4.8), and accepted them.
4. Date range matches the fetch window; event types show one kind of
   missing (4.9).
5. **The re-run test:** restart R (Session → Restart R — the desk
   empties), run the script top to bottom again, and get the same
   ledger and the same counts. Rebuild-from-raw, identical result:
   that's reproducibility, experienced firsthand.

## 6. Commit checkpoint

```bash
git add .
git commit -m "Phase 2: clean and harmonize 84.5K events into device families; write clean_events table"
git push
```

Also flip Phase 2's row to ✅ in the README's build log — keeping that
table honest is part of the phase.

## 7. What could go wrong (mini-FAQ)

**"I don't see clean_events anywhere — only raw, clean, and
clean_for_db"** — you're looking at the desk (RStudio's Environment
pane), which shows only temporary R objects, never database tables.
`clean_events` lives in the cabinet: the file
`data/processed/orthowatch.db`. Check with `dbListTables(con)`. If that
returns only `"raw_events"`, the `dbWriteTable()` line hasn't run yet —
run step 4.10, then ask again. If the desk objects have meanwhile
vanished (R restarted), re-run the script from the top: rebuilding
them takes seconds, by design.

**`invalid 'na.print' specification` when printing** — you called
`print(n = 25)` on a base data.frame instead of a tibble. Base R's
print has no `n` argument, and R's *partial argument matching* silently
maps `n` onto the unrelated `na.print` — an error mentioning an
argument you never typed. Fix: convert once at the border
(`dbReadTable(...) |> as_tibble()`), as the script does. Lesson: when
an R error names an argument you didn't write, suspect partial
matching.

**`could not find function "clean_events"`** — you skipped
`source("R/clean_events.R")`, or your working directory isn't the
project root (check with `getwd()`; opening the `.Rproj` file fixes
it).

**`database is locked`** — another connection is holding the DB (a
forgotten `con` from an earlier session, or an open DB browser).
`dbDisconnect(con)` everywhere, or restart R (Session → Restart R).

**Ledger shows unparseable dates** — a handful is normal (malformed
strings in the source). They're kept as NA and simply drop out of
date-based analyses. Hundreds+? Inspect:
`raw |> filter(is.na(suppressWarnings(lubridate::ymd(date_received)))) |> count(date_received)`.

**More rows vanished at dedup than duplicates found in 4.3** — stop.
Something beyond the two known duplicates was collapsed. Compare
`nrow(raw)` with the dedup ledger line and revisit 4.3's query before
trusting anything downstream.

**Numbers differ from these docs** — expected: MAUDE updates weekly,
so fetch date changes counts. What must NOT differ: two runs on the
*same* raw files (checkpoint 5's re-run test).

## 8. Two ways to run everything (running tally)

| Capability | Manual path (now) | Automatic path (later) |
|---|---|---|
| Fetch data | `python ingest/fetch_maude.py` | Phase 7 one-command pipeline |
| Load to DB | `python ingest/load_to_sqlite.py` | same |
| Clean | `analysis/01_clean_events.R` step by step | same pipeline, calling the same `R/clean_events.R` engine |
| Inspect | queries in the analysis scripts | Shiny dashboard (Phase 6) |

---

**Next:** `04-phase-3-trending.md` — reports per family per month,
control-chart thinking, and the first honest trend curves — where the
question shifts from "is the data usable?" to "what is it saying?"
