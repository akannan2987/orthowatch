[← README](../README.md) · [All docs in order](../README.md#the-tutorial-in-order)

# Glossary — every term in this project, in plain words

No prior knowledge assumed. If a word in any doc, script, or comment
isn't here and isn't obvious, that's a bug — please open an issue (or,
if this is your project, add it).

---

## The medical & regulatory words

**Medical device** — any manufactured object used in medical care: hip
implants, knee implants, bone plates, screws, pacemakers, even
tongue depressors. This project looks at orthopedic (bone- and
joint-related) devices.

**Adverse event** — a bad thing that happened involving a device: it
broke, came loose, caused injury or infection. "Adverse" simply means
harmful or unwanted.

**Adverse event report** — the form somebody (a hospital, the
manufacturer, sometimes a patient) fills out and sends to the
authorities when an adverse event happens: which device, what
happened, when, plus a short written description. One report = one
form. One row in our data = one report.

**MDR (Medical Device Report)** — the FDA's official name for such a
form. Same thing as "adverse event report" in this project.

**FDA** — the US Food and Drug Administration: the government agency
that oversees medicines and medical devices in the United States.

**MAUDE** — the FDA's big public collection of device adverse event
reports (millions of them). Our data comes from here. (In 2026 the FDA
began folding MAUDE into a newer system called AEMS.)

**Post-market surveillance (PMS)** — watching how a product behaves
AFTER it is on the market ("post-market" = after launch), mainly by
monitoring adverse event reports. Manufacturers are legally required
to do this. This whole project is a small post-market surveillance
system.

**Signal** — a warning sign in the data: some device suddenly
generating more reports, or a worse kind of report, than expected. A
signal is a reason to *investigate*, never proof by itself that a
device is bad.

**Complaint trending** — counting reports over time (per month, per
device) and watching how the counts move. The bread and butter of
surveillance.

**Event type** — MAUDE's category for how bad the event was:
Malfunction (device misbehaved, nobody hurt), Injury, Death, or Other.

**Narrative** — the free-text description on a report ("patient
presented with pain, revision surgery revealed a fractured stem...").
Phase 5 mines these texts.

**GxP / regulated environment** — shorthand for industries (medicines,
devices) where the law dictates how carefully work must be documented
and proven. Explains this project's obsessions: never altering raw
data, logging everything, making results reproducible.

**Traceability** — being able to walk any number in a final report
backwards to the exact source it came from. Our fetch log and
"source_file" columns exist for this.

## The data words

**Data / dataset** — information organized for a computer to work
with. Our dataset: ~84,000 adverse event reports.

**Table** — data arranged in rows and columns, like a spreadsheet.
One **row** = one thing (here: one report). One **column** = one fact
about it (here: date, device name, event type...).

**Database** — an organized container holding one or more tables,
stored as a file (or on a server), built for asking precise questions
fast. Think: a filing cabinet for tables.

**SQLite** — the database program we use. Its special trait: the whole
database is a single ordinary file on your disk —
`data/processed/orthowatch.db`. No server, no account.

**SQL** — the near-universal language for asking databases questions.
`SELECT COUNT(*) FROM clean_events` = "how many rows does the
clean_events table have?". Reads almost like English.

**Query** — one question asked in SQL.

**Raw data** — data exactly as it arrived from the source, untouched —
like raw ingredients. **Clean data** — the same data after tidying
(fixing dates, unifying spellings, removing duplicates), fit for
analysis.

**`raw_events`** — the database table holding all fetched reports
exactly as the FDA sent them. Never modified. Our evidence.

**`clean_events`** — the second table: the same reports after Phase
2's tidying. Everything downstream (trends, dashboard, report) uses
this one.

**Duplicate** — the same report appearing more than once (e.g. the FDA
received an updated version of a form). We keep the newest.

**Missing value / NA** — "this field was left blank". R marks it `NA`.
We count and label missing data; we never silently throw it away.

**JSON** — the text format data arrives in from the API: labeled,
nested lists, readable by humans and machines.

**API** — a website built for programs instead of people: your script
requests a specific address, and instead of a web page it receives
data. The FDA runs one at api.fda.gov.

**API key** — a personal password-like code identifying you to an API.
Ours lives in an environment variable, never in code or Git.

**Ingestion** — the act of pulling data from a source into your own
storage. Phase 1.

**Pipeline** — a chain of automated steps where each one's output
feeds the next: fetch → load → clean → analyze → report.

**Device family** — OUR simplification (created in Phase 2): every
report gets sorted into Hip prosthesis / Knee prosthesis / Bone plate /
Spinal fixation / Other / Unknown, so hundreds of spelling variants
become five analyzable groups.

**"Other" (device family)** — the leftover bin: the label a report
gets when its device name matches none of the family rules. Every
sorting system needs an "everything else" box; ours is usually empty
because the download only requested devices the rules already cover.
Not to be confused with `event_type = "Other"`, which is the FDA's own
tick-box for what kind of bad event occurred — same word, unrelated
column.

## The tools

**R** — a programming language built for statistics and data analysis.
Our main language.

**RStudio** — the friendly workbench application we write and run R
in. Its **Console** pane runs R code; its **Terminal** pane talks to
the computer itself (Git, Python).

**R session** — one running instance of R: your temporary desk.
Objects you create live here and vanish when R restarts. The
**Environment pane** (top-right in RStudio) lists them. Database
tables live in the cabinet (the .db file), NOT here.

**Object** — anything you've created on the desk and given a name:
`raw`, `clean`, a number, a function.

**Script** — a file of code meant to be run top to bottom, like a
recipe (`analysis/01_clean_events.R`). **Function** — a reusable named
tool that scripts call (`clean_events()`); ours live in `R/`.

**Package / library** — an add-on toolbox of functions someone
published (tidyverse, DBI...). `install.packages()` fetches one;
`library()` opens it for the session.

**tidyverse** — the most popular family of R packages for everyday
data work. Includes `dplyr` (table verbs like mutate/filter/count),
`stringr` (text), `lubridate` (dates), `tibble` (friendlier tables).

**Pipe (`|>`)** — R punctuation meaning "then":
`data |> clean() |> count()` = take data, then clean, then count.

**Python** — a general-purpose programming language; here it does one
job: fetching data from the API (Phase 1).

**venv / renv** — tools that give a project its own private, sealed
set of packages (venv for Python, renv for R) plus a written list of
exact versions, so anyone can recreate the setup identically.

**Environment variable** — a named value attached to your terminal
session that programs can read; how we hand the API key to the script
without writing it in code.

**Git** — a save-game system for the project: every meaningful change
becomes a named snapshot (**commit**) you can always return to.
**Push** — upload your commits to GitHub. **GitHub** — the public
website where this repository lives.

**Repository (repo)** — the project folder, with its Git history
attached.

**.gitignore** — a list of files Git must pretend not to see (our
data, our secrets, machine junk).

**SQLite has no date type** — a quirk worth its own entry: SQLite
stores dates as plain text. We use ISO format ("2023-04-15") because
it sorts correctly as text.

**Quarto** — a tool that weaves text + code + the code's outputs into
one polished, self-updating report (Phase 7).

**Shiny** — an R framework that turns analysis code into an
interactive web dashboard with dropdowns and charts (Phase 6).

**Dashboard** — an interactive screen for exploring data: pick a
device family, see its trend.

**Frontend / backend** — the part a human sees and clicks (dashboard)
vs. the machinery working behind it (fetching, cleaning, computing).

**Reproducible** — the property that re-running the project's code on
the same inputs produces identical results, every time, on anyone's
machine. The quiet goal behind almost every design choice here.

## The statistics words (added in Phase 3)

**Time series** — the same quantity measured repeatedly at regular
intervals, kept in time order: e.g. reports per month for five years
= a sequence of 60 numbers. This project tracks four of them, one per
device family. Trending = studying a time series.

**Average (mean)** — the typical level of a series: total divided by
number of months.

**Standard deviation (σ, "sigma")** — how far a series typically
strays from its average month to month. For counts of independently
arriving events (Poisson-distributed: variance = mean), σ equals the
square root of the average — the fact control limits are built on.

**Control chart** — a standard quality-control tool: plot the series,
draw its average, and draw a band three standard deviations wide
around it. Inside the band = ordinary variation, no action; outside =
something changed, investigate. Everyday version: a 30-minute commute
varying 27–33 is normal; a 55-minute one means something happened. Points inside the band = ordinary randomness; points
outside = something changed, investigate.

**Control limits (UCL / LCL)** — the band's edges: Upper and Lower
Control Limit, at average ± 3 × standard deviation. Above the UCL = unusually many
reports; below the LCL = unusually few (both matter).

**Three sigma (3σ)** — the conventional width of the band. Wide enough
that ordinary randomness essentially never crosses it, so crossings
deserve attention.

**Signal vs. noise** — noise is ordinary random variation; a signal
is a movement too large to be that. A flag marks a signal — it says
"investigate", never "unsafe".

**Baseline** — the period or level you compare against ("the rest of
2020" vs. "the spike window").

**ggplot2** — R's standard charting package: declare what maps to what
(x, y, color), then add layers (lines, points, bands, panels).

**Facet** — ggplot's word for splitting one chart into small multiples
— one panel per device family.

**plotly** — a widely used library for interactive charts (hover,
zoom, click-to-hide) that run in a web browser. In R,
`plotly::ggplotly()` converts an existing ggplot chart — same chart,
browser superpowers.

**Widget / htmlwidget** — an interactive chart packaged as an HTML
file: open it in any browser, no R needed. "Self-contained" means the
file embeds everything it needs (hence its size, ~4 MB).

**GitHub Pages** — GitHub's free static-website hosting: flip a switch
in a repo's settings and files from a chosen folder are served as real
web pages at `https://username.github.io/repo/...`. Static = plain
files only; perfect for our widget, unusable for a Shiny app.

**Client-side vs. server-side** — where interactive work happens.
Client-side: in the visitor's browser (our plotly hover/zoom — the
file carries its own JavaScript, any file host suffices). Server-side:
on a running program elsewhere (Shiny re-running R code on every click
— needs a live server). The line between them decides where something
can be hosted.

## The signal-detection words (added in Phase 4)

**Contingency table (2x2)** — four boxes sorting every report by two
yes/no questions at once: in family D or not × mentions problem P or
not. The cells are named a, b, c, d; every statistic in Phase 4 is
arithmetic on them.

**Odds** — "with, per without": 8 reports with a problem per 92
without = odds of 8/92. A proportion says 8 in 100; odds repackage
the same fact.

**PRR (Proportional Reporting Ratio)** — how many times larger a
problem's *share* is among one family's reports than among everyone
else's. PRR 3 = three times the share.

**ROR (Reporting Odds Ratio)** — the same comparison using odds:
(a×d)/(b×c). Comes with a textbook confidence-interval formula, which
is why vigilance teams like it.

**Confidence interval (95% CI)** — the range of values plausibly
compatible with the data, luck included. If even its lower end sits
above 1, "just luck" stops being a comfortable explanation.

**Chi-square (χ²)** — a surprise score for a table: how far it sits
from what pure no-association would produce. ≥ 4 is the conventional
bar (roughly p < 0.05).

**Evans rule** — the published first-pass signal definition used in
vigilance: PRR ≥ 2 AND χ² ≥ 4 AND a ≥ 3, all at once.

**Disproportionality analysis** — the family name for all of the
above: finding (device, problem) pairs reported out of proportion.

**Signal** *(sharpened)* — a pair passing the rule: over-REPORTED,
which is a reason to investigate, never proof of risk.

**Unit test** — a claim about code, written as code: "given this tiny
hand-worked input, the function must return exactly this." Lives in
`tests/`, runs on command, turns red when broken.

**testthat** — R's standard testing package: `test_that("claim", {
expect_equal(got, wanted) })`. `Rscript tests/run_tests.R` runs the
whole suite.

**Integer overflow** — when arithmetic exceeds what a number type can
hold (R's integers cap near 2.1 billion) and the result silently
becomes NA or nonsense. This project's test suite caught exactly this
in the χ² denominator before the code met real data.

## The text-mining words (added in Phase 5)

**Corpus** — a collection of texts treated as one dataset; ours is
~84K report narratives.

**Token / tokenization** — a token is one countable piece of text
(here: a lowercase word); tokenization is the chopping that produces
them. Computers don't read — they count tokens.

**Stop words** — filler words removed before counting: standard
English filler ("the", "was") plus *domain* filler that appears in
virtually every narrative here ("patient", "device"). Removing them
is judgment, documented in the engine.

**Term frequency / rate** — how often a word occurs, always
normalized (per 10,000 words of that family's text), because
families write different amounts — same denominator lesson as PRR.

**Rate ratio / log2 ratio (words)** — Phase 4's 2×2 arithmetic with
words in the cells: a word's rate in one family divided by its rate
everywhere else, smoothed against zeros; reported as log2 (+1 =
twice, +3 = eight times).

**Boilerplate** — template text reporters paste into many narratives;
inflates word counts without carrying case-specific meaning. The
reason counting guides but reading decides.

**Bigram** — a two-word token ("metal debris"); useful when single
words lose the phrase. A documented extension, not used in the core.

## The dashboard words (added in Phase 6)

**Shiny** — R's framework for web applications: a web page with a
live R session behind it, recomputing whatever the user's
interactions require. Contrast with the published plotly pages,
which carry their JavaScript with them and need no server.

**UI / server** — every Shiny app's two halves: `ui` declares what
exists on the page; `server` declares how each output is computed
from the inputs. Shared names ("trend_families") are the wiring.

**Reactivity** — the spreadsheet model: outputs re-run automatically
when anything they read changes. You write the recipe once; the
dependencies do the scheduling.

**input$ / output$** — the server's two doorways: `input$x` reads the
current value of the UI control named "x"; assigning
`output$y <- render...` fills the UI area named "y".

**event_data()** — plotly's bridge into Shiny: returns the details of
the last click on a named chart, including each point's `customdata`
— in this project, a `"family|key"` string that maps a click back to
data.

**Parameterized SQL** — queries with `?` placeholders where values
travel separately from the SQL text. The standard defense against
SQL injection (a value can never rewrite the query).

**localhost / port** — `127.0.0.1` ("localhost") is this very
machine; a port is one of its numbered doors, letting many network
programs coexist. `Listening on http://127.0.0.1:4321` = "your
laptop, door 4321, nothing on the internet."

**DT / data table** — the DT package renders data frames as
interactive browser tables (sort, search, page) — used for the
drill-downs.

**Deploy** — putting an app where others reach it. A Shiny app needs
a server that runs R (e.g. shinyapps.io's free tier) — a roadmap
item here, not a phase.

## The pipeline words (added in Phase 7)

**Pipeline** — an assembly line for data: raw material in one end,
finished tables/figures/reports out the other, through stages that
each do one job in a fixed order.

**Stage** — one job in the pipeline, wrapped as a callable function
taking the config. Wrapped as functions, stages can be run by the
runner, the tests, a scheduler, or an app — not just by a human
remembering an order.

**Configuration (config)** — the settings panel, kept apart from the
machinery: every tunable number in one file the stages read. Change
a threshold, rerun, done.

**Runner / orchestration** — the thin script that decides which
stages run, in what order, with timing, stopping loudly on failure.
Runners wrap pipelines; they never contain them. (Industrial-scale
orchestrators — Airflow, Prefect — are this same idea with
scheduling and retries; ours is the honest 60-line version.)

**Final gate** — running the test suite as the pipeline's last
stage, failing the whole run if any test fails: the pipeline
verifies its own math every time, which is what makes it trustable
unattended.

**Offline mode** — the default run skips the fetch: everything
downstream of the raw files reruns freely; the expensive,
credentialed, external step is opt-in by name.

**Quarto / executable document** — prose with embedded code chunks;
*rendering* runs the chunks against the data and weaves results into
the text. Numbers are computed, never pasted, so the document cannot
drift out of date. (Quarto ships inside RStudio.)

**Render** — running an executable document to produce its output
file (here: one self-contained HTML carrying its own charts and
styles).

**Reproducibility** — the demonstrated (not just promised) property
that the same inputs give the same outputs: same raw files → same
database → same tables and figures → same report, with the one
outside-our-control rung stated honestly (a fresh fetch may differ,
because MAUDE itself revises).

## The workbench words (added in Phase 8)

**Workbench** — an app that *runs the work*, not just displays it: a
dashboard plus the controls (run stages, query, render) that operate
the system underneath.

**Blocking / synchronous** — while one R session computes, it cannot
also serve clicks: the browser waits. A Shiny session is a
single-lane bridge; honest tools show progress and state costs
instead of pretending.

**Background / asynchronous** — the second lane: a separate worker
process runs the long job while the UI stays live (`future` +
`promises` in Shiny). The production pattern for long stages —
roadmap here, by choice.

**Defense in depth** — two independent safeguards where one would
do, so a bug in either still leaves you protected. The query
console: a text validator AND a read-only connection.

**Read-only connection** — a database connection opened with a flag
(SQLite's `SQLITE_RO`) that makes writes impossible at the database
level, regardless of what SQL reaches it.

**SQL console** — a box that runs typed SQL against the database and
shows the result. Powerful and hazardous — hence the two locks.

**Application state / refresh** — data an app holds in memory (the
loaded tables). When the ground truth changes (a pipeline run), the
state must be deliberately swapped — here a `reactiveVal` refilled
by a Reload button, so every dependent output recomputes.

## The data-access words (added in Phase 8b)

**Query dictionary** — the whitelist of API fields a search may use,
each with meaning and example. APIs only understand their own
vocabulary; the dictionary is that vocabulary, written down and
enforced.

**Validate before the network** — check user input against the
dictionary locally, so errors are instant and informative instead of
silent zero-match downloads minutes later.

**Dry run** — resolve and print exactly what an action WOULD do
(here: the API queries a scope builds) without doing it. The
developer's look-before-you-leap.

**CLI arguments** — the `--flag value` settings a script accepts on
its command line; how one program (R) hands a scope to another
(Python) across the seam.

**CSV / XLSX / JSON** — the three export dialects: plain rows for
everything, spreadsheets for people, structured text for programs.

**Export** — data leaving the system in a format someone else's tool
can open. An instrument without exports is a silo.

**Environment variable** — a named value a process carries, inherited
*at birth from its parent* and from nowhere else. An `export` in one
Terminal window does not reach an app launched from the Dock — they
have different parents.

**.Renviron** — a file R reads at every session start, setting
environment variables for the session and everything it launches.
The reliable home for an API key in an R project — and always
gitignored, because secrets never enter version control.

**on.exit()** — R's "no matter how this function ends, run this"
hook. House rule learned the hard way: register it *before* the
risky action it cleans up after, so even an interrupt in between
cannot leave the mess behind.

## The provenance words (added in Phase 8c)

**State vs ledger** — the balance and the statement: state is what
things are now (the result tables); the ledger is every event that
made them so (run_history). Serious systems keep both.

**Provenance** — the answer to "which run produced what I'm looking
at?" — here, one sentence on the Overview tab, read from the
ledger's latest line.

**Run history / audit trail** — the append-only record of
consequential events (probes, fetches, pipeline runs, report
renders), failures included, stored in the database so it survives
restarts and serves both the app and the Terminal.

**Versioned result sets** — the roadmap storey above the ledger:
per-run copies of every result table so old runs remain viewable.
Powerful, storage-hungry, touches every query — a phase, not a
patch.
