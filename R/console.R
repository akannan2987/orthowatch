# console.R — the read-only query console's engine (Phase 8)
# ============================================================
# A SQL console in an app is a gift and a hazard: ad hoc questions
# without writing R, but one careless (or malicious) statement could
# rewrite the database. The professional answer is DEFENSE IN DEPTH -
# two independent locks, either of which alone would suffice:
#
#   Lock 1: VALIDATE the text - only a single SELECT (or WITH, for
#           CTEs) is accepted; anything else is refused with a reason.
#   Lock 2: OPEN READ-ONLY - the database connection itself is opened
#           with SQLite's read-only flag, so even a statement that
#           somehow slipped the validator CANNOT write.
#
# Belt and braces: if one lock has a bug, the other still holds.

# Words that mean "this is not a read": refused even inside a SELECT-
# looking statement, because some (ATTACH, PRAGMA) can change state.
.FORBIDDEN <- c("INSERT", "UPDATE", "DELETE", "DROP", "ALTER",
                "CREATE", "REPLACE", "PRAGMA", "ATTACH", "DETACH",
                "VACUUM", "REINDEX", "TRIGGER")

is_select_only <- function(sql) {
  # Returns list(ok = TRUE/FALSE, reason = "...").
  s <- trimws(sql)
  if (nchar(s) == 0)
    return(list(ok = FALSE, reason = "empty query"))
  # One statement only: a semicolon may end the query, never split it.
  body <- sub(";\\s*$", "", s)
  if (grepl(";", body, fixed = TRUE))
    return(list(ok = FALSE, reason = "one statement at a time (no ';' inside)"))
  # Must READ: first word SELECT, or WITH (a CTE that feeds a SELECT).
  first <- toupper(sub("\\s.*$", "", body))
  if (!first %in% c("SELECT", "WITH"))
    return(list(ok = FALSE, reason = "only SELECT queries are allowed here"))
  # No state-changing keywords anywhere (as whole words).
  words <- toupper(unlist(strsplit(body, "[^A-Za-z_]+")))
  hit <- intersect(words, .FORBIDDEN)
  if (length(hit) > 0)
    return(list(ok = FALSE,
                reason = paste0("forbidden keyword: ", hit[1],
                                " (this console is read-only)")))
  list(ok = TRUE, reason = "")
}

run_readonly_query <- function(db_path, sql, max_rows = 200) {
  # Lock 1: validate the text.
  check <- is_select_only(sql)
  if (!check$ok) stop(check$reason, call. = FALSE)
  # Lock 2: a connection that CANNOT write, by construction.
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path,
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  # Fetch at most max_rows + 1: the extra row tells us truncation
  # happened without ever pulling a million rows into RAM.
  res <- DBI::dbSendQuery(con, sql)
  on.exit(DBI::dbClearResult(res), add = TRUE, after = FALSE)
  out <- DBI::dbFetch(res, n = max_rows + 1)
  truncated <- nrow(out) > max_rows
  if (truncated) out <- utils::head(out, max_rows)
  attr(out, "truncated") <- truncated
  out
}
