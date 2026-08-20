# test-pipeline.R — the pipeline's contract
# ===========================================
# Not "does the whole pipeline run" (that's run_pipeline.R itself, on
# real data) — these pin the pieces the runner and Phase 8's app rely
# on: the config's shape, the registry's completeness, and one stage
# exercised end to end against a temporary database.

test_that("config has every field the stages read", {
  cfg <- pipeline_config()
  expect_true(all(c("db_path", "figures_dir", "interactive_dir",
                    "families", "min_a", "min_problem_total",
                    "top_n_signals", "min_total_terms",
                    "publish_interactive") %in% names(cfg)))
  expect_length(cfg$families, 4)
})

test_that("the registry is complete, ordered, and default-offline", {
  expect_equal(names(PIPELINE_STAGES),
               c("probe", "fetch", "load", "clean", "trend", "signals",
                 "terms", "test", "report"))
  expect_true(all(vapply(PIPELINE_STAGES, is.function, logical(1))))
  expect_false(any(c("probe", "fetch") %in% DEFAULT_STAGES))  # opt-in
  expect_equal(DEFAULT_STAGES[length(DEFAULT_STAGES)], "test")  # final gate
})

test_that("stage_trend runs end to end against a temporary database", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "clean_events", tibble::tibble(
    report_number = as.character(1:240),
    device_family = "Hip prosthesis",
    year_month = rep(sprintf("2020-%02d", 1:12), each = 20)
  ))
  DBI::dbDisconnect(con)

  cfg <- pipeline_config()
  cfg$db_path <- tmp
  cfg$figures_dir <- tempdir()
  cfg$publish_interactive <- FALSE     # no docs/ writes from a test
  cfg$families <- "Hip prosthesis"

  stage_trend(cfg)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  m <- DBI::dbGetQuery(con, "SELECT * FROM monthly_trends")
  DBI::dbDisconnect(con)
  expect_equal(nrow(m), 12)
  expect_true(all(c("center", "ucl", "lcl", "status") %in% names(m)))
})
