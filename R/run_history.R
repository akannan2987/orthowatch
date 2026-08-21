# run_history.R — the project's ledger (Phase 8c)
# =================================================
# STATE vs LEDGER, the bank-account analogy: your balance is STATE
# (what things are now); your statement is the LEDGER (every event
# that made it so). The five result tables are this project's state;
# run_history is its statement. Provenance - "which run produced what
# I'm looking at?" - is just reading the ledger's latest line.
#
# What gets recorded: the CONSEQUENTIAL events - probes and fetches
# (they spend API budget), pipeline runs (they change state), report
# renders (they publish). Read-only queries are deliberately NOT
# recorded: a ledger spammed by every glance is noise, not history.
# Failures ARE recorded - an honest ledger keeps its bad days.

record_run <- function(db_path, kind, detail, outcome, summary = "",
                       seconds = NA_real_) {
  # Appends one row; creates the table on first use.
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS run_history (
      run_at   TEXT,   -- when (ISO, local time)
      kind     TEXT,   -- probe | fetch | pipeline | report
      detail   TEXT,   -- scope or stage list
      outcome  TEXT,   -- ok | error
      summary  TEXT,   -- the run's key lines, one string
      seconds  REAL
    )")
  DBI::dbExecute(con, "
    INSERT INTO run_history (run_at, kind, detail, outcome, summary, seconds)
    VALUES (?, ?, ?, ?, ?, ?)",
    params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  kind, detail, outcome,
                  substr(summary, 1, 2000), seconds))
  invisible(TRUE)
}

read_run_history <- function(db_path, n = 50) {
  # Newest first. Returns an empty tibble (right columns) if the
  # ledger doesn't exist yet - a fresh clone has no history, and
  # that must not be an error.
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path,
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (!"run_history" %in% DBI::dbListTables(con))
    return(tibble::tibble(run_at = character(), kind = character(),
                          detail = character(), outcome = character(),
                          summary = character(), seconds = numeric()))
  DBI::dbGetQuery(con, "
    SELECT * FROM run_history ORDER BY run_at DESC, rowid DESC LIMIT ?",
    params = list(n)) |> tibble::as_tibble()
}
