# 03_signal_detection.R — Phase 4: which problems belong to which devices?
# =========================================================================
# Run LINE BY LINE alongside docs/05-phase-4-signal-detection.md.
#
# The story: trending (Phase 3) told us WHEN report counts moved.
# This script asks the sharper vigilance question: is a specific
# PROBLEM over-represented for a specific DEVICE FAMILY, compared to
# all the others? Each family is its own denominator, so the answer is
# immune to the overall volume trends that flooded Phase 3 with flags.

library(DBI)
library(RSQLite)
library(dplyr)
library(tibble)
library(tidyr)
library(stringr)
library(ggplot2)

source("R/signal_detection.R")   # build_problem_table(), signal_stats(),
                                 # plot_top_signals()

con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")


# ── 1. Pull the events and check the denominators ────────────────────

events <- dbGetQuery(con, "
  SELECT report_number, device_family, product_problems
  FROM clean_events
") |> as_tibble()

events |> count(device_family, sort = TRUE)
# These per-family totals are the (a+b) denominators of every 2x2.


# ── 2. Un-glue the problems: one row per (report, problem) ───────────

problems <- build_problem_table(events)
nrow(problems)
n_distinct(problems$product_problem)

# The most-mentioned problems overall — the c+a margins of the tables:
problems |> count(product_problem, sort = TRUE) |> head(10)


# ── 3. Compute every 2x2 at once ─────────────────────────────────────
# One call: for every (family, problem) pair with enough data,
# the four cells, PRR, chi2, ROR with its confidence interval,
# and the Evans yes/no.

stats <- signal_stats(events)
nrow(stats)          # how many (family, problem) pairs made the cut
glimpse(stats)


# ── 4. The signal table — strongest first ────────────────────────────

signals <- stats |> filter(evans_signal) |> arrange(desc(prr))
nrow(signals)
signals |>
  select(device_family, product_problem, a, prr, chi2, ror, ror_lo, ror_hi) |>
  print(n = 15)

# How to read one row aloud: "problem X appears in family Y's reports
# PRR times as often as in everyone else's; the confidence interval
# around the odds ratio stays above 1, so it isn't a small-numbers
# fluke." Over-REPORTED, not proven risk — a signal opens questions.


# ── 5. Read each family's list, then write your verdict ─────────────

signals |>
  group_by(device_family) |>
  slice_max(prr, n = 5) |>
  ungroup() |>
  select(device_family, product_problem, a, prr, ror)

# Sanity questions while reading (answers differ per dataset — this is
# your judgment step, like Phase 3's deep dive):
#  * Do the top signals make CLINICAL sense for that device? (Loosening
#    for joint implants, breakage for plates, migration for spinal
#    hardware would all be textbook.)
#  * Is any signal driven by one reporter's vocabulary rather than the
#    device? (Cross-check suspicious ones against Phase 3's findings.)
#  * Where does the vague "Adverse Event Without Identified Device or
#    Use Problem" land? It is everywhere, so it should struggle to be
#    OVER-represented anywhere — if it still signals for a family,
#    that echoes a reporting-behavior pattern, not a device pattern.
# Then write a dated, initialed verdict comment at the bottom of this
# file, exactly as in Phase 3.


# ── 6. The forest plot: each family's strongest signals ─────────────

p_signals <- plot_top_signals(stats)
p_signals

dir.create("figures", showWarnings = FALSE)
ggsave("figures/signals_top.png", p_signals,
       width = 9, height = 10, dpi = 150)


# ── 6b. The interactive twin — where hover genuinely earns its keep ──
# The static plot truncates problem names and hides the counts; the
# tooltip carries the FULL name plus the whole 2x2 (a/b/c/d), PRR,
# chi2, and the ROR with its CI. Preview lands in figures/ (already
# covered by the figures/*.html ignore rule).

library(plotly)
ip_signals <- plot_top_signals_interactive(stats)
ip_signals                    # renders in RStudio's Viewer pane

htmlwidgets::saveWidget(ip_signals, "figures/signals_top.html",
                        selfcontained = TRUE)


# ── 6c. Publish it (same deliberate act as Phase 3's 8c) ─────────────
# Pages is already set up from Phase 3 — publishing a second chart is
# just: copy into docs/interactive/, commit, push.

file.copy("figures/signals_top.html",
          "docs/interactive/signals_top.html", overwrite = TRUE)
cat("After commit+push, live at:\n",
    "https://akannan2987.github.io/orthowatch/interactive/signals_top.html\n")


# ── 7. Run the automated tests (Terminal, project root) ─────────────
#   Rscript tests/run_tests.R
# Expected: [ FAIL 0 | WARN 0 | SKIP 0 | PASS 22 ]
# The doc's step 4.8 includes a deliberate break-and-fix exercise —
# do it once; watching a test fail teaches more than watching it pass.


# ── 8. Write signal_stats into the cabinet ──────────────────────────
# The dashboard (Phase 6) gets a signals view for free.

dbWriteTable(con, "signal_stats",
             stats |> mutate(evans_signal = as.integer(evans_signal)),
             overwrite = TRUE)
dbListTables(con)  # expect: clean_events, monthly_trends, raw_events, signal_stats

dbDisconnect(con)


# ── Signal verdict (2026-08-19, AK) ─────────────────────────────────
# 64 of 312 (family, problem) pairs pass the Evans rule. Top signals
# are clinically coherent per family: a metal-degradation cluster for
# hips (Corroded, Material Erosion, Biocompatibility, Degraded),
# slippage/integrity for spinal fixation, wear/instability for knees
# (Unstable, Naturally Worn, Loss of Bond), and an intraoperative-fit
# cluster for bone plates (Difficult to Advance, Entrapment,
# Device-Device Incompatibility). The vague catch-all category (26,093
# mentions — the largest by far) signals for NO family, exactly as the
# method predicts for a category present everywhere: a built-in
# validation. Caveats recorded: "No Apparent Adverse Event" signaling
# for spinal fixation (PRR 7.8) more plausibly reflects one reporter's
# coding habits than devices; the hip "Contaminated During
# Manufacture" signal (a=1012, PRR 32) was not checked for time or
# reporter concentration (cf. the Phase 3 batch-submission pattern).
# Signals = over-reported, never proven risk.
