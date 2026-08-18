# 00_verify_ingest.R — Phase 1 checkpoint
# =========================================
# Run this LINE BY LINE in RStudio (cursor on a line, press Cmd/Ctrl+Enter).
# It proves the Python-built database is readable from R — the handoff
# point where Python's job ends and R's begins.

library(DBI)        # DBI = R's standard interface for talking to databases
library(RSQLite)    # the SQLite driver DBI uses under the hood

# Open a connection to the database file. Think of a connection as a
# phone line to the database: open it, ask questions, hang up.
con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")

# 1. What tables exist? Expect: "raw_events"
dbListTables(con)

# 2. How many rows? (Your number will differ from anyone else's — MAUDE
#    updates weekly. Tens of thousands is the expected ballpark.)
dbGetQuery(con, "SELECT COUNT(*) AS n_rows FROM raw_events")

# 3. First look at the data itself: 5 rows, a few columns.
#    SQL reads almost like English: SELECT columns FROM table LIMIT n.
dbGetQuery(con, "
  SELECT report_number, date_received, event_type, generic_name
  FROM raw_events
  LIMIT 5
")

# 4. Which device names dominate? GROUP BY collapses rows sharing a
#    value; COUNT(*) counts each group. Spot the inconsistent spellings
#    and formats — that mess is exactly what Phase 2 exists to fix.
dbGetQuery(con, "
  SELECT generic_name, COUNT(*) AS n
  FROM raw_events
  GROUP BY generic_name
  ORDER BY n DESC
  LIMIT 15
")

# 5. Reports per year — a first, crude glimpse of the trending to come.
#    substr(date_received, 1, 4) chops 'YYYYMMDD' down to 'YYYY'.
dbGetQuery(con, "
  SELECT substr(date_received, 1, 4) AS year, COUNT(*) AS n
  FROM raw_events
  GROUP BY year
  ORDER BY year
")

# Always hang up the phone line when done.
dbDisconnect(con)
