# test-interactive_meta.R — the dashboard's click plumbing
# ==========================================================
# Phase 6's drill-downs depend on two properties of the interactive
# charts: a `source` id (so Shiny knows WHICH chart was clicked) and
# customdata on every point (so a click maps back to "family|key").
# These tests pin both, for all three charts.

toy_monthly <- function() {
  tibble::tibble(device_family = "Hip prosthesis",
                 year_month = rep(sprintf("2020-%02d", 1:12),
                                  times = c(rep(100, 11), 200))) |>
    count_monthly(families = "Hip prosthesis") |>
    add_control_limits()
}
toy_stats <- function() {
  tibble::tibble(
    report_number = as.character(1:1100),
    device_family = c(rep("Hip prosthesis", 100), rep("Knee prosthesis", 1000)),
    product_problems = c(rep("P", 20), rep("Q", 80), rep("P", 100), rep("Q", 900))
  ) |> signal_stats(min_a = 1, min_problem_total = 1)
}
toy_dist <- function() {
  tibble::tibble(report_number = as.character(1:40),
                 device_family = rep(c("Hip prosthesis", "Knee prosthesis"), each = 20),
                 narrative = rep(c("corrosion taper debris", "tibial wear insert"), each = 20)) |>
    tokenize_narratives() |> count_terms() |> distinctive_terms(min_total = 5)
}

meta <- function(widget) plotly::plotly_build(widget)$x

test_that("trends chart carries source id and family|month customdata", {
  x <- meta(plot_trends_interactive(toy_monthly(), source = "trends"))
  expect_equal(x$source, "trends")
  cd <- unlist(lapply(x$data, function(d) d$customdata))
  expect_true(any(grepl("^Hip prosthesis\\|2020-12$", cd)))
})

test_that("signals chart carries source id and family|problem customdata", {
  x <- meta(plot_top_signals_interactive(toy_stats(), source = "signals"))
  expect_equal(x$source, "signals")
  cd <- unlist(lapply(x$data, function(d) d$customdata))
  expect_true(any(grepl("^Hip prosthesis\\|P$", cd)))
})

test_that("terms chart carries source id and family|word customdata", {
  x <- meta(plot_term_scatter_interactive(toy_dist(), min_per_10k = 0,
                                          source = "terms"))
  expect_equal(x$source, "terms")
  cd <- unlist(lapply(x$data, function(d) d$customdata))
  expect_true(any(grepl("^Hip prosthesis\\|corrosion$", cd)))
})
