# test-console.R — both locks of the read-only console
# ======================================================
# The console's promise is "read-only by construction". These tests
# pin the validator's refusals AND prove the second lock holds even
# when handed a write attempt directly.

test_that("the validator accepts reads", {
  expect_true(is_select_only("SELECT * FROM clean_events")$ok)
  expect_true(is_select_only("  select count(*) from signal_stats;")$ok)
  expect_true(is_select_only(
    "WITH t AS (SELECT device_family FROM clean_events) SELECT * FROM t")$ok)
})

test_that("the validator refuses everything else, with reasons", {
  expect_false(is_select_only("")$ok)
  expect_false(is_select_only("DELETE FROM clean_events")$ok)
  expect_false(is_select_only("DROP TABLE clean_events")$ok)
  expect_false(is_select_only("PRAGMA writable_schema = 1")$ok)
  expect_false(is_select_only(
    "SELECT 1; DELETE FROM clean_events")$ok)          # no smuggling
  expect_match(is_select_only("UPDATE x SET a = 1")$reason, "SELECT")
})

test_that("the read-only connection is the second lock", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "t", data.frame(x = 1:300))
  DBI::dbDisconnect(con)

  out <- run_readonly_query(tmp, "SELECT * FROM t", max_rows = 200)
  expect_equal(nrow(out), 200)                         # capped...
  expect_true(attr(out, "truncated"))                  # ...and says so

  expect_error(run_readonly_query(tmp, "DELETE FROM t"),
               "SELECT")                               # lock 1 refuses
  # And lock 2: even bypassing the validator, SQLite itself refuses.
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp, flags = RSQLite::SQLITE_RO)
  expect_error(DBI::dbExecute(con, "DELETE FROM t"))
  DBI::dbDisconnect(con)
})
