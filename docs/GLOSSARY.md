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
