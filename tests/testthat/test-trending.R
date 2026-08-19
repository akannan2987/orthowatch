# test-trending.R — the Phase 3 smoke checks, made permanent
# ============================================================
# Hand-worked: eleven months of 100 with June entirely absent and
# December at 200 -> after zero-filling, center = 100, sigma = 10,
# UCL = 130, LCL = 70; December flags above, June below.

make_test_monthly <- function() {
  months <- format(seq.Date(as.Date("2020-01-01"), as.Date("2020-12-01"),
                            by = "month"), "%Y-%m")
  months <- setdiff(months, "2020-06")
  tibble::tibble(
    device_family = "Hip prosthesis",
    year_month = rep(months, times = c(rep(100, 10), 200))
  ) |> count_monthly(families = "Hip prosthesis")
}

test_that("a missing month is zero-filled, not silently dropped", {
  m <- make_test_monthly()
  expect_equal(nrow(m), 12)
  expect_equal(m$n[m$month_date == as.Date("2020-06-01")], 0)
})

test_that("c-chart limits match hand calculation", {
  lim <- add_control_limits(make_test_monthly())
  expect_equal(unique(lim$center), 100, tolerance = 1e-9)
  expect_equal(unique(lim$ucl), 130, tolerance = 1e-9)
  expect_equal(unique(lim$lcl), 70,  tolerance = 1e-9)
})

test_that("flags fire in both directions", {
  f <- flagged_months(add_control_limits(make_test_monthly()))
  expect_equal(nrow(f), 2)
  expect_equal(f$status[f$month_date == as.Date("2020-12-01")], "above limit")
  expect_equal(f$status[f$month_date == as.Date("2020-06-01")], "below limit")
})
