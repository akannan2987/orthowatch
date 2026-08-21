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

test_that("versioned writes keep vintages, migrate legacy, and retain N", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  # a pre-8d table: no run_id column
  DBI::dbWriteTable(con, "monthly_trends", data.frame(x = 1:3))

  write_versioned(con, "monthly_trends", data.frame(x = 4:5), "run_20260821_090000")
  write_versioned(con, "monthly_trends", data.frame(x = 6:9), "run_20260821_100000")

  ids <- result_vintages(con, "monthly_trends")
  expect_equal(ids, c("run_20260821_100000", "run_20260821_090000", "legacy"))

  expect_equal(nrow(read_result(con, "monthly_trends")), 4)          # latest
  expect_equal(read_result(con, "monthly_trends",
                           "run_20260821_090000")$x, 4:5)            # chosen
  expect_equal(read_result(con, "monthly_trends", "legacy")$x, 1:3)  # migrated
  expect_false("run_id" %in% names(read_result(con, "monthly_trends")))

  # rerun same id replaces its own vintage only (idempotent)
  write_versioned(con, "monthly_trends", data.frame(x = 10), "run_20260821_100000")
  expect_equal(read_result(con, "monthly_trends")$x, 10)

  # retention trims oldest first ('legacy' ages out)
  write_versioned(con, "monthly_trends", data.frame(x = 11),
                  "run_20260821_110000", keep_runs = 2)
  expect_equal(result_vintages(con, "monthly_trends"),
               c("run_20260821_110000", "run_20260821_100000"))
  DBI::dbDisconnect(con)
})

test_that("run ids sort chronologically and the ledger carries them", {
  expect_match(new_run_id(), "^run_\\d{8}_\\d{6}$")
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "t", data.frame(x = 1)); DBI::dbDisconnect(con)
  record_run(tmp, "pipeline", "trend", "ok", run_id = "run_20260821_120000")
  expect_equal(read_run_history(tmp)$run_id[1], "run_20260821_120000")
})
