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
  cfg$run_id <- "run_20260821_130000"

  stage_trend(cfg)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  m <- read_result(con, "monthly_trends")
  ids <- result_vintages(con, "monthly_trends")
  DBI::dbDisconnect(con)
  expect_equal(nrow(m), 12)
  expect_true(all(c("center", "ucl", "lcl", "status") %in% names(m)))
  expect_equal(ids, "run_20260821_130000")   # the vintage is labeled
})

test_that("fetch scope validation refuses what the API can't answer", {
  expect_true(validate_fetch_scope()$ok)
  expect_true(validate_fetch_scope(families = "hip_prosthesis",
                                   year_from = 2023, year_to = 2024,
                                   search = 'product_problems:"Corroded"')$ok)
  expect_false(validate_fetch_scope(families = "shoulder_thing")$ok)
  expect_false(validate_fetch_scope(year_from = 2024, year_to = 2020)$ok)
  expect_false(validate_fetch_scope(search = "bogus_field:xyz")$ok)
  expect_match(validate_fetch_scope(search = "just words")$reason, "field:value")
})

test_that("build_fetch_args threads the scope into CLI arguments", {
  cfg <- pipeline_config()
  cfg$fetch_families <- c("hip_prosthesis", "bone_plate")
  cfg$fetch_year_from <- 2023; cfg$fetch_year_to <- 2024
  cfg$fetch_search <- 'event_type:Malfunction'
  a <- build_fetch_args(cfg, probe = TRUE)
  expect_true(all(c("--probe", "--families", "--year-from", "--search") %in% a))
  expect_true("hip_prosthesis,bone_plate" %in% a)
  # default config adds no scope flags at all (script defaults rule)
  expect_equal(build_fetch_args(pipeline_config()), "ingest/fetch_maude.py")
})

test_that("analysis scope narrows a run's vintage to the chosen slice", {
  tmp <- tempfile(fileext = ".db")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbWriteTable(con, "clean_events", tibble::tibble(
    report_number = as.character(1:480),
    device_family = rep(c("Hip prosthesis", "Spinal fixation"), each = 240),
    year_month = rep(rep(sprintf("20%d-%02d", rep(20:21, each = 12), 1:12),
                         each = 10), 2)
  ))
  DBI::dbDisconnect(con)

  cfg <- pipeline_config()
  cfg$db_path <- tmp; cfg$figures_dir <- tempdir()
  cfg$publish_interactive <- FALSE
  cfg$run_id <- "run_20260821_170000"
  cfg$analysis_families  <- "Spinal fixation"
  cfg$analysis_year_from <- "2021"
  cfg$analysis_year_to   <- "2021"

  stage_trend(cfg)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  m <- read_result(con, "monthly_trends")
  DBI::dbDisconnect(con)
  expect_equal(unique(m$device_family), "Spinal fixation")   # one family
  expect_equal(nrow(m), 12)                                  # one year
  expect_true(all(substr(m$year_month, 1, 4) == "2021"))
})
