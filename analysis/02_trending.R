# 02_trending.R — Phase 3: from counts to judgment
# ==================================================
# Run this LINE BY LINE alongside docs/04-phase-3-trending.md, which
# shows the expected output of every step and what it means.
#
# The story of this script:
#   1. Rebuild the monthly counts two ways (SQL, then dplyr) and see
#      they agree — same question, two languages.
#   2. Fill in silent months (absent is not zero!).
#   3. Draw the first trend chart and LOOK before computing anything.
#   4. Add control limits — the statistical definition of "unusual".
#   5. Read the flagged-months table.
#   6. Deep-dive the biggest flag: WHAT drove it?
#   7. Save the figures and write the monthly_trends table for the
#      dashboard and report to reuse.

library(DBI)
library(RSQLite)
library(dplyr)
library(tibble)
library(tidyr)
library(ggplot2)

source("R/trending.R")   # the engine: count_monthly(), add_control_limits(),
                         # flagged_months(), plot_trends()

con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")


# ── 1. Monthly counts, in SQL ────────────────────────────────────────
# The exact query Phase 2 ended with — the database does the counting.

monthly_sql <- dbGetQuery(con, "
  SELECT device_family, year_month, COUNT(*) AS n
  FROM clean_events
  WHERE device_family IN ('Hip prosthesis', 'Knee prosthesis',
                          'Bone plate', 'Spinal fixation')
  GROUP BY device_family, year_month
  ORDER BY device_family, year_month
") |> as_tibble()

monthly_sql |> head(5)
nrow(monthly_sql)    # families x months that had at least one report


# ── 2. The same counts, in dplyr — same task, different language ─────
# We pull the events into R once (only the columns trending needs) and
# let dplyr do the counting. Compare the two results: they must agree.

events <- dbGetQuery(con, "
  SELECT report_number, device_family, year_month, event_type,
         manufacturer, product_problems
  FROM clean_events
") |> as_tibble()

monthly_dplyr <- events |>
  filter(device_family %in% c("Hip prosthesis", "Knee prosthesis",
                              "Bone plate", "Spinal fixation")) |>
  count(device_family, year_month, name = "n") |>
  arrange(device_family, year_month)

# The agreement check: TRUE means SQL and dplyr counted identically.
all.equal(as.data.frame(monthly_sql), as.data.frame(monthly_dplyr))


# ── 3. Absent is not zero: fill the silent months ────────────────────
# count_monthly() (from the engine) redoes the count AND completes the
# grid: every family x every month, zeros filled in where no reports
# arrived. It also converts year_month text into real dates for the
# time axis.

monthly <- count_monthly(events)
nrow(monthly)          # families x ALL months (4 x 60 = 240 if none missing)
sum(monthly$n == 0)    # how many silent months existed (often 0 here)


# ── 4. First look — plot BEFORE computing ────────────────────────────
# Discipline worth keeping: look at the raw shape before any statistics.
# (Limits aren't computed yet, so we plot plain lines here.)

ggplot(monthly, aes(month_date, n)) +
  geom_line(color = "steelblue4") +
  facet_wrap(~ device_family, scales = "free_y", ncol = 1) +
  labs(title = "Monthly reports by device family (raw view)",
       x = NULL, y = "reports per month") +
  theme_minimal()

# Look at each panel and just... notice things. The bone plate hump in
# mid-2020. The knee ramp-up through 2024. Any dips. Write down what
# your eyes flag — then let the statistics have their turn.


# ── 5. Control limits: the statistical definition of "unusual" ───────

monthly_limits <- add_control_limits(monthly)   # k = 3 sigma by default

# The per-family summary: average, standard deviation, and the limits.
monthly_limits |>
  distinct(device_family, center, sigma, ucl, lcl) |>
  mutate(across(where(is.numeric), ~ round(.x, 1)))

# The full chart: grey band = ordinary randomness; dots outside = flags.
p_trends <- plot_trends(monthly_limits)
p_trends


# ── 6. The flagged-months table — what a reviewer would read ─────────

flags <- flagged_months(monthly_limits)
print(flags, n = 30)

# distance = how many standard deviations from the average. 3 is the bar;
# 18 is a klaxon. Note flags come in both directions: "above limit"
# (unusually many reports) AND "below limit" (unusually few — reporting
# gaps and real-world slowdowns show up here).


# ── 7. Deep dive: WHAT drove the biggest flag? ───────────────────────
# Flags say WHEN something changed; the narrative fields say WHAT.
# We compare the flagged window against the months before it.
# separate_rows() un-glues the ';'-joined product_problems so each
# problem counts individually.

bone_2020 <- events |>
  filter(device_family == "Bone plate",
         year_month >= "2020-01", year_month <= "2020-12") |>
  mutate(window = if_else(year_month >= "2020-07" & year_month <= "2020-10",
                          "spike (Jul-Oct)", "baseline (rest of 2020)"))

# (a) Which reported problems grew?
bone_2020 |>
  separate_rows(product_problems, sep = ";") |>
  filter(product_problems != "") |>
  count(window, product_problems, sort = TRUE) |>
  group_by(window) |>
  slice_head(n = 5) |>
  ungroup()

# (b) Is the spike broad-based or concentrated in one manufacturer?
bone_2020 |>
  count(window, manufacturer, sort = TRUE) |>
  group_by(window) |>
  slice_head(n = 5) |>
  ungroup()

# Read the two tables side by side: if one problem type or one
# manufacturer dominates the spike window but not the baseline, the
# spike is CONCENTRATED — the classic fingerprint of a specific issue
# (or of one company submitting a batch of reports at once). If the
# spike is spread evenly, think process/reporting causes instead.
# Either way: this is where a real team would open an investigation —
# and where our public data analysis stops drawing conclusions.


# ── 8. Save the figures (they go in the README) ──────────────────────

dir.create("figures", showWarnings = FALSE)
ggsave("figures/trend_by_family.png", p_trends,
       width = 9, height = 10, dpi = 150)

# A close-up of the bone plate panel for the deep-dive story:
p_bone <- plot_trends(filter(monthly_limits, device_family == "Bone plate"))
ggsave("figures/trend_bone_plate.png", p_bone,
       width = 9, height = 3.5, dpi = 150)

list.files("figures")


# ── 8b. Optional: the interactive twin (plotly) ──────────────────────
# Same chart, browser superpowers: hover any dot for its exact numbers,
# drag a box to zoom into the 2020 spike (double-click resets), click a
# legend entry to hide/show a status group.
# One-time setup: install.packages("plotly")  then  renv::snapshot()
# The file saved here is a throwaway local preview (gitignored);
# PUBLISHING it as a web page is the separate, deliberate step in 8c.

library(plotly)
ip <- plot_trends_interactive(monthly_limits)
ip                          # renders in RStudio's Viewer pane

htmlwidgets::saveWidget(ip, "figures/trend_by_family.html",
                        selfcontained = TRUE)
# Open it in your actual browser for the full experience:
# double-click the file in Finder, or run: browseURL("figures/trend_by_family.html")


# ── 8c. Publish the interactive chart via GitHub Pages ───────────────
# figures/ holds throwaway previews (regenerated every run, ignored by
# Git). PUBLISHING is a deliberate act: copy the widget into
# docs/interactive/ — which IS committed — and GitHub Pages serves it
# as a real web page. Re-run this block only when results change.
# One-time Pages setup lives in the doc, section 4.8c.

dir.create("docs/interactive", showWarnings = FALSE)
file.copy("figures/trend_by_family.html",
          "docs/interactive/trend_by_family.html", overwrite = TRUE)

# .nojekyll = a marker file telling GitHub Pages to serve docs/ as
# plain files instead of trying to build a website out of the folder.
file.create("docs/.nojekyll")

cat("Published copy staged. After commit+push and one-time Pages setup:\n",
    "https://akannan2987.github.io/orthowatch/interactive/trend_by_family.html\n")


# ── 9. Write monthly_trends into the cabinet ─────────────────────────
# The dashboard (Phase 6) and report (Phase 7) will read this table
# instead of recomputing — one engine, one result, many consumers.

monthly_trends_db <- monthly_limits |>
  mutate(year_month = format(month_date, "%Y-%m")) |>
  select(device_family, year_month, n, center, sigma, ucl, lcl, status)

dbWriteTable(con, "monthly_trends", monthly_trends_db, overwrite = TRUE)
dbListTables(con)   # expect: clean_events, monthly_trends, raw_events

dbDisconnect(con)


# ── Deep-dive verdict (2026-08-19, AK) ───────────────────────────────
# Normalizing for unequal windows (8 baseline vs 4 spike months), the
# Jul-Oct 2020 bone-plate spike is CONCENTRATED: one manufacturing
# site's monthly reports rose ~3.4x (others ~1.3-1.8x), and the
# fastest-growing problem category is the unspecified one ("Adverse
# Event Without Identified Device or Use Problem", ~3.2x), while
# specific failure modes like Fracture actually fell per month.
# Most consistent with a batch/retrospective submission by one
# reporter, not a device failing more often. Also noted: 152/240
# months flag overall because the series trend strongly — a global-
# mean c-chart over-flags non-stationary series; rolling-baseline
# limits are the documented refinement (roadmap).
