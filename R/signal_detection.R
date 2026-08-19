# signal_detection.R — Phase 4: the signal detection engine
# ============================================================
# Trending (Phase 3) asks "is this MONTH unusual for this family?"
# Signal detection asks the sharper vigilance question:
#   "is this PROBLEM unusually associated with this DEVICE FAMILY,
#    compared to all the other families?"
#
# THE IDEA IN ONE PARAGRAPH
#   For every (family, problem) pair, sort ALL reports into the 2x2
#   table (see docs/img/contingency_2x2.png): a = family's reports
#   mentioning the problem, b = family's reports not mentioning it,
#   c and d = the same split for every other family. Then compare
#   PROPORTIONS: if 8% of knee reports mention "Loosening" while 2% of
#   everyone else's do, that problem is over-represented for knees —
#   regardless of how many reports knees generate overall. Because each
#   family is its own denominator, this measure is immune to the
#   volume trends that flooded Phase 3 with flags.
#
# THE STATISTICS (standard pharmacovigilance practice)
#   PRR  = (a/(a+b)) / (c/(c+d))     "proportional reporting ratio"
#   ROR  = (a*d) / (b*c)             "reporting odds ratio"
#   chi2 = N*(ad-bc)^2 / ((a+b)(c+d)(a+c)(b+d))   a surprise score
#   ROR 95% CI: exp( ln(ROR) +/- 1.96*sqrt(1/a+1/b+1/c+1/d) )
#   Evans signal rule (the published rule of thumb used in vigilance):
#     PRR >= 2  AND  chi2 >= 4  AND  a >= 3
#   Zero cells make ratios blow up; the standard fix (Haldane) adds 0.5
#   to every cell for the ROR/CI when any cell is zero.

library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)

SIGNAL_FAMILIES <- c("Hip prosthesis", "Knee prosthesis",
                     "Bone plate", "Spinal fixation")


build_problem_table <- function(events) {
  # One row per (report, problem). Reports list problems ';'-joined;
  # separate_rows un-glues them. distinct() ensures a report counts a
  # given problem ONCE even if the source listed it twice.
  events |>
    filter(device_family %in% SIGNAL_FAMILIES) |>
    separate_rows(product_problems, sep = ";") |>
    mutate(product_problem = str_squish(product_problems)) |>
    filter(product_problem != "") |>
    distinct(report_number, device_family, product_problem)
}


signal_stats <- function(events, min_a = 3, min_problem_total = 30) {
  # The orchestrator: events in, one row of statistics per
  # (family, problem) pair out.
  #
  #   min_a             Evans' floor: pairs with fewer than 3 reports
  #                     are too thin to call anything.
  #   min_problem_total problems mentioned fewer than ~30 times overall
  #                     are dropped from the table entirely — they
  #                     produce noisy ratios and an unreadably long
  #                     output. (Tunable; a judgment, stated openly.)

  # Denominators: how many REPORTS each family has in total — computed
  # from ALL reports, including those listing no problems at all.
  fam_totals <- events |>
    filter(device_family %in% SIGNAL_FAMILIES) |>
    count(device_family, name = "n_family")
  n_total <- sum(fam_totals$n_family)

  problems <- build_problem_table(events)

  problems |>
    count(device_family, product_problem, name = "a") |>
    # total mentions of each problem across ALL families:
    group_by(product_problem) |>
    mutate(problem_total = sum(a)) |>
    ungroup() |>
    filter(problem_total >= min_problem_total) |>
    left_join(fam_totals, by = "device_family") |>
    mutate(
      b = n_family - a,                    # family, without the problem
      c = problem_total - a,               # others, with the problem
      d = (n_total - n_family) - c,        # others, without it
      # CRITICAL, caught by the unit tests: R counts are 32-bit
      # integers (max ~2.1e9), and chi2's denominator multiplies four
      # of them — easily past that ceiling, silently producing NA.
      # Convert to floating-point numbers before any arithmetic.
      across(c(a, b, c, d), as.numeric),
      # PRR and the chi-square surprise score, straight from the table:
      prr  = (a / (a + b)) / (c / (c + d)),
      chi2 = (a + b + c + d) * (a * d - b * c)^2 /
             ((a + b) * (c + d) * (a + c) * (b + d)),
      # ROR with the Haldane 0.5 correction when any cell is zero
      # (otherwise a zero cell makes the ratio 0 or infinite):
      corr = if_else(a == 0 | b == 0 | c == 0 | d == 0, 0.5, 0),
      ror    = ((a + corr) * (d + corr)) / ((b + corr) * (c + corr)),
      se_log = sqrt(1/(a + corr) + 1/(b + corr) +
                    1/(c + corr) + 1/(d + corr)),
      ror_lo = exp(log(ror) - 1.96 * se_log),
      ror_hi = exp(log(ror) + 1.96 * se_log),
      # The Evans rule, as a plain logical column:
      evans_signal = (prr >= 2) & (chi2 >= 4) & (a >= min_a)
    ) |>
    select(device_family, product_problem, a, b, c, d,
           prr, chi2, ror, ror_lo, ror_hi, evans_signal) |>
    arrange(desc(evans_signal), desc(prr))
}


plot_top_signals <- function(stats, top_n = 5) {
  # A forest-style plot of each family's strongest signals: the dot is
  # the ROR, the horizontal line its 95% confidence interval, on a log
  # axis (so 0.5 and 2 sit symmetrically around 1). The dashed line at
  # 1 means "reported no more than everyone else" — a signal's whole
  # interval sits right of it.
  top <- stats |>
    filter(evans_signal) |>
    group_by(device_family) |>
    slice_max(prr, n = top_n) |>
    ungroup() |>
    mutate(label = str_trunc(product_problem, 42))

  ggplot(top, aes(x = ror, y = reorder(label, ror))) +
    geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
    # horizontal error bars via orientation="y" (geom_errorbarh was
    # deprecated in ggplot2 4.0 — same picture, current grammar)
    geom_errorbar(aes(xmin = ror_lo, xmax = ror_hi),
                  orientation = "y", width = 0.2, color = "grey40") +
    geom_point(color = "red3", size = 2.2) +
    scale_x_log10() +
    facet_wrap(~ device_family, scales = "free_y", ncol = 1) +
    labs(
      title = "Strongest disproportionality signals per device family",
      subtitle = "Dot = reporting odds ratio (ROR); line = 95% CI; all shown pass the Evans rule (PRR>=2, chi2>=4, a>=3)",
      x = "reporting odds ratio (log scale)", y = NULL,
      caption = "Signals mean over-represented in reports, never proven risk."
    ) +
    theme_minimal(base_size = 11)
}


plot_top_signals_interactive <- function(stats, top_n = 5) {
  # The interactive twin of plot_top_signals() — and here interactivity
  # fixes a real limitation of the static version: paper truncates
  # problem names to fit the axis, and hides the counts behind each
  # dot. The hover tooltip carries the FULL problem name, the whole
  # 2x2 (a/b/c/d), PRR, chi-square, and the ROR with its interval.
  # Phase 6's dashboard calls this function directly.
  requireNamespace("plotly", quietly = TRUE)

  top <- stats |>
    filter(evans_signal) |>
    group_by(device_family) |>
    slice_max(prr, n = top_n) |>
    ungroup() |>
    mutate(
      label = str_trunc(product_problem, 42),
      tooltip = sprintf(
        paste0("%s\n%s\n",
               "a=%d  b=%d  c=%d  d=%d\n",
               "PRR %.1f   chi2 %.0f\n",
               "ROR %.1f  (95%% CI %.1f-%.1f)"),
        device_family, product_problem,
        a, b, c, d, prr, chi2, ror, ror_lo, ror_hi
      )
    )

  p <- suppressWarnings(
    ggplot(top, aes(x = ror, y = reorder(label, ror))) +
      geom_vline(xintercept = 1, linetype = "dashed", color = "grey50") +
      geom_errorbar(aes(xmin = ror_lo, xmax = ror_hi),
                    orientation = "y", width = 0.2, color = "grey40") +
      geom_point(aes(text = tooltip), color = "red3", size = 2.2) +
      scale_x_log10() +
      facet_wrap(~ device_family, scales = "free_y", ncol = 1) +
      labs(title = "Strongest disproportionality signals (interactive)",
           x = "reporting odds ratio (log scale)", y = NULL) +
      theme_minimal(base_size = 11)
  )

  plotly::ggplotly(p, tooltip = "text") |>
    plotly::config(displaylogo = FALSE)
}
