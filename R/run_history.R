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

new_run_id <- function() {
  # Timestamp-based ids sort chronologically as plain strings - the
  # property every "latest vintage" query below relies on.
  format(Sys.time(), "run_%Y%m%d_%H%M%S")
}

record_run <- function(db_path, kind, detail, outcome, summary = "",
                       seconds = NA_real_, run_id = NA_character_) {
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
      seconds  REAL,
      run_id   TEXT    -- ties this ledger line to its result vintage
    )")
  # Ledgers created before Phase 8d lack the run_id column - migrate
  # in place, once, losing nothing.
  cols <- DBI::dbGetQuery(con, "PRAGMA table_info(run_history)")$name
  if (!"run_id" %in% cols)
    DBI::dbExecute(con, "ALTER TABLE run_history ADD COLUMN run_id TEXT")
  DBI::dbExecute(con, "
    INSERT INTO run_history (run_at, kind, detail, outcome, summary,
                             seconds, run_id)
    VALUES (?, ?, ?, ?, ?, ?, ?)",
    params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  kind, detail, outcome,
                  substr(summary, 1, 2000), seconds, run_id))
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


# ── Versioned result tables: one table, many vintages ────────────────
# Instead of each run OVERWRITING monthly_trends / signal_stats /
# narrative_terms (destroying yesterday to make today), every run
# APPENDS its rows tagged with its run_id - like a wine cellar: one
# rack, many vintages, each labeled. Old vintages stay viewable;
# retention keeps the rack from growing forever.

write_versioned <- function(con, name, df, run_id, keep_runs = 10) {
  df$run_id <- run_id
  if (!name %in% DBI::dbListTables(con)) {
    DBI::dbWriteTable(con, name, df)
  } else {
    cols <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", name, ")"))$name
    if (!"run_id" %in% cols) {
      # Pre-8d table: migrate in place - existing rows become the
      # 'legacy' vintage. Nothing is lost.
      DBI::dbExecute(con, paste0("ALTER TABLE ", name,
                                 " ADD COLUMN run_id TEXT DEFAULT 'legacy'"))
      DBI::dbExecute(con, paste0("UPDATE ", name,
                                 " SET run_id = 'legacy' WHERE run_id IS NULL"))
    }
    # Idempotent per run: rerunning a stage replaces ITS vintage only.
    DBI::dbExecute(con, paste0("DELETE FROM ", name, " WHERE run_id = ?"),
                   params = list(run_id))
    DBI::dbAppendTable(con, name, df)
  }
  # Retention: keep the newest keep_runs vintages (ids sort by time;
  # 'legacy' sorts before any run_* id, so it ages out first).
  ids <- DBI::dbGetQuery(con, paste0(
    "SELECT DISTINCT run_id FROM ", name, " ORDER BY run_id DESC"))$run_id
  for (old_id in utils::tail(ids, -keep_runs))
    DBI::dbExecute(con, paste0("DELETE FROM ", name, " WHERE run_id = ?"),
                   params = list(old_id))
  invisible(TRUE)
}

read_result <- function(con, name, run_id = NULL) {
  # Serve one vintage - by default the latest - WITHOUT the run_id
  # column, so every consumer (app, report, tests) sees exactly the
  # schema it always saw. Tables never versioned read through as-is.
  cols <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", name, ")"))$name
  if (!"run_id" %in% cols)
    return(DBI::dbGetQuery(con, paste0("SELECT * FROM ", name)))
  if (is.null(run_id)) {
    run_id <- DBI::dbGetQuery(con, paste0(
      "SELECT MAX(run_id) AS id FROM ", name))$id
    if (is.na(run_id)) return(DBI::dbGetQuery(con, paste0(
      "SELECT * FROM ", name, " WHERE 0")))
  }
  out <- DBI::dbGetQuery(con, paste0("SELECT * FROM ", name,
                                     " WHERE run_id = ?"),
                         params = list(run_id))
  out[, setdiff(names(out), "run_id"), drop = FALSE]
}

result_vintages <- function(con, name = "monthly_trends") {
  # The vintages available on a table, newest first - the run
  # selector's menu.
  if (!name %in% DBI::dbListTables(con)) return(character())
  cols <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", name, ")"))$name
  if (!"run_id" %in% cols) return(character())
  DBI::dbGetQuery(con, paste0(
    "SELECT DISTINCT run_id FROM ", name, " ORDER BY run_id DESC"))$run_id
}
