# 01_clean_events.R — Phase 2: run the cleaning, write clean_events
# ==================================================================
# Run this LINE BY LINE first (cursor on a line, Cmd/Ctrl+Enter) to see
# each step happen — then, in future, run it top-to-bottom as one script.
#
# What it does:
#   1. Reads raw_events from SQLite (the evidence, untouched)
#   2. Investigates the known quirks BEFORE fixing them
#   3. Applies the cleaning engine from R/clean_events.R
#   4. Inspects the results (especially the "Other" bucket)
#   5. Writes a NEW table, clean_events — raw_events is never modified

library(DBI)
library(RSQLite)
library(dplyr)
library(tibble)   # for as_tibble(); tibbles = tidyverse's friendlier tables

# Load the cleaning engine. source() runs a file's code in your session,
# which here means "make its functions available".
source("R/clean_events.R")

con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")


# ── 1. Read the raw table ────────────────────────────────────────────

# dbReadTable() returns a base-R data.frame. We convert it to a
# *tibble* — the tidyverse's enhanced table type — right away. Tibbles
# print politely (a screenful, with column types) and their print()
# understands n = 25. Base data.frames don't have an n argument, and
# thanks to R's partial argument matching, print(n = 25) on one gets
# silently matched to the unrelated na.print argument and errors with
# "invalid 'na.print' specification". Converting once at the border
# spares every later step that trap.
raw <- dbReadTable(con, "raw_events") |> as_tibble()
nrow(raw)   # expect the number from your load summary (e.g. 84,549)


# ── 2. Look the quirks in the eye before fixing them ─────────────────

# (a) The duplicated report_numbers — the load summary said there were
#     a couple. HAVING filters *groups* the way WHERE filters rows.
dbGetQuery(con, "
  SELECT report_number, COUNT(*) AS n
  FROM raw_events
  GROUP BY report_number
  HAVING n > 1
")

# Pull one of them up in full and compare the rows: same event twice?
# A follow-up? Two devices from overlapping queries? Reading actual
# duplicates beats theorizing about them. (Replace the id with one
# from the query above.)
# raw |> filter(report_number == "PASTE-ONE-HERE") |> glimpse()

# (b) The blank event types (the mysterious 5 from the load summary):
raw |> count(event_type) |> arrange(n)

# (c) The name chaos, quantified: how many DISTINCT raw spellings are
#     we about to collapse into 5 families?
n_distinct(raw$generic_name)


# ── 3. Clean ─────────────────────────────────────────────────────────

# One call runs the whole documented pipeline and prints the ledger.
clean <- clean_events(raw)


# ── 4. Inspect the result before trusting it ─────────────────────────

# (a) The family mapping, cross-tabulated against a sample of the raw
#     names it consumed — spot-check that nothing landed absurdly:
clean |>
  count(device_family, generic_name_std, sort = TRUE) |>
  group_by(device_family) |>
  slice_head(n = 3) |>
  ungroup()

# (b) THE OTHER BUCKET — the most important check on this page.
#     These are names our rules did NOT recognize. Read them. If you
#     see obvious hips/knees/plates/spines here, the rules in
#     classify_device_family() need another case — that's a judgment
#     call you make with your eyes, not one the code makes for you.
clean |>
  filter(device_family == "Other") |>
  count(generic_name_std, sort = TRUE) |>
  print(n = 25)

# (c) Date sanity: parsed range should match the fetch window.
range(clean$date_received_parsed, na.rm = TRUE)

# (d) Event types now have exactly one kind of missing:
clean |> count(event_type_clean, sort = TRUE)


# ── 5. Write clean_events (a NEW table; raw stays untouched) ─────────

# We keep only the columns downstream phases need — a deliberate,
# visible selection rather than dragging everything along.
clean_for_db <- clean |>
  select(
    report_number, mdr_report_key,
    date_received_iso, year_month,
    event_type = event_type_clean,
    device_family, generic_name_std,
    brand_name, manufacturer = manufacturer_std, model_number,
    n_devices_on_report, product_problems, narrative, source_file
  )

dbWriteTable(con, "clean_events", clean_for_db, overwrite = TRUE)
dbListTables(con)   # expect: "clean_events" AND "raw_events"

# First taste of Phase 3: reports per family per month, straight off
# the clean table. This one query is the seed of the entire trending
# dashboard.
dbGetQuery(con, "
  SELECT device_family, year_month, COUNT(*) AS n_reports
  FROM clean_events
  GROUP BY device_family, year_month
  ORDER BY device_family, year_month
") |> head(10)

dbDisconnect(con)
