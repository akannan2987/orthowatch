# test-signal_detection.R — the math must match hand calculation
# ================================================================
# Every expectation here was first computed BY HAND on a small 2x2
# table, so a green run means the code agrees with arithmetic a human
# verified — the whole point of a unit test.

# The hand-worked example:
#   a=20, b=80, c=100, d=900   (N = 1100)
#   PRR  = (20/100) / (100/1000)          = 2.0
#   ROR  = (20*900) / (80*100)            = 2.25
#   chi2 = 1100*(20*900-80*100)^2 /
#          (100*1000*120*980)             = 9.3537...
#   ln(ROR)=0.81093, se=0.27132
#   CI   = exp(0.81093 -/+ 1.96*0.27132)  = [1.322, 3.830]

toy_events <- function(a, b, c, d) {
  # Build a minimal events table that produces exactly one 2x2 with
  # the requested cells: family "Hip prosthesis" vs "Knee prosthesis",
  # problem "P" vs a filler problem "Q" (so 'without P' rows exist).
  tibble::tibble(
    report_number = as.character(seq_len(a + b + c + d)),
    device_family = c(rep("Hip prosthesis", a + b),
                      rep("Knee prosthesis", c + d)),
    product_problems = c(rep("P", a), rep("Q", b),
                         rep("P", c), rep("Q", d))
  )
}

test_that("PRR, ROR, chi2 and CI match the hand-worked example", {
  s <- signal_stats(toy_events(20, 80, 100, 900),
                    min_a = 1, min_problem_total = 1) |>
    dplyr::filter(device_family == "Hip prosthesis",
                  product_problem == "P")
  expect_equal(s$a, 20)
  expect_equal(s$b, 80)
  expect_equal(s$c, 100)
  expect_equal(s$d, 900)
  expect_equal(s$prr,  2.0,    tolerance = 1e-9)
  expect_equal(s$ror,  2.25,   tolerance = 1e-9)
  expect_equal(s$chi2, 9.3537, tolerance = 1e-3)
  expect_equal(s$ror_lo, 1.322, tolerance = 1e-3)
  expect_equal(s$ror_hi, 3.830, tolerance = 1e-3)
})

test_that("the Evans rule fires exactly when all three conditions hold", {
  s <- signal_stats(toy_events(20, 80, 100, 900),
                    min_a = 1, min_problem_total = 1) |>
    dplyr::filter(device_family == "Hip prosthesis",
                  product_problem == "P")
  expect_true(s$evans_signal)          # PRR 2.0 >= 2, chi2 9.35 >= 4, a 20 >= 3

  # Same proportions, but too few reports: a=2 fails the a>=3 floor
  # (min_a left at its default of 3).
  s2 <- signal_stats(toy_events(2, 8, 10, 90),
                     min_problem_total = 1) |>
    dplyr::filter(device_family == "Hip prosthesis",
                  product_problem == "P")
  expect_false(s2$evans_signal)
})

test_that("a zero cell yields finite ROR and CI (Haldane correction)", {
  # b = 0: every Hip report mentions P. Uncorrected ROR would be Inf.
  s <- signal_stats(toy_events(5, 0, 10, 90),
                    min_a = 1, min_problem_total = 1) |>
    dplyr::filter(device_family == "Hip prosthesis",
                  product_problem == "P")
  expect_true(is.finite(s$ror))
  expect_true(is.finite(s$ror_lo) && is.finite(s$ror_hi))
})

test_that("a report listing the same problem twice counts once", {
  ev <- tibble::tibble(
    report_number = c("r1", "r2", "r3"),
    device_family = c("Hip prosthesis", "Hip prosthesis", "Knee prosthesis"),
    product_problems = c("P;P", "Q", "P")   # r1 lists P twice
  )
  pt <- build_problem_table(ev)
  expect_equal(sum(pt$report_number == "r1" & pt$product_problem == "P"), 1)
})
