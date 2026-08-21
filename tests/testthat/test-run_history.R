# test-run_history.R — the ledger's contract
# ============================================
test_that("recording creates the ledger and appends, newest first", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "t", data.frame(x = 1))   # a db with no ledger yet
  DBI::dbDisconnect(con)

  record_run(tmp, "pipeline", "trend, signals", "ok",
             "[trend] 240 rows", seconds = 6.2)
  Sys.sleep(1)                                     # distinct timestamps
  record_run(tmp, "fetch", "bone_plate 2024", "error", "HTTP 403")

  h <- read_run_history(tmp)
  expect_equal(nrow(h), 2)
  expect_equal(h$kind[1], "fetch")                 # newest first
  expect_equal(h$outcome[2], "ok")
  expect_true(is.na(h$seconds[1]))                 # failures keep NA timing
})

test_that("an absent ledger reads as empty, never as an error", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "t", data.frame(x = 1))
  DBI::dbDisconnect(con)
  h <- read_run_history(tmp)
  expect_equal(nrow(h), 0)
  expect_true(all(c("run_at", "kind", "detail", "outcome",
                    "summary", "seconds") %in% names(h)))
})

test_that("long summaries are truncated, not refused", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "t", data.frame(x = 1))
  DBI::dbDisconnect(con)
  record_run(tmp, "pipeline", "all", "ok", strrep("x", 5000))
  expect_lte(nchar(read_run_history(tmp)$summary[1]), 2000)
})
