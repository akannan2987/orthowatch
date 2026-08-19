# trending.R — Phase 3: the trending engine
# ============================================
# Reusable functions that turn clean_events into monthly trend series
# with control limits — the statistical heart of complaint trending.
#
# Same division of labor as Phase 2:
#   R/         = functions you CALL (this file)
#   analysis/  = scripts you RUN (02_trending.R walks these functions
#                through the real data, step by step)
#
# THE STATISTICAL IDEA, IN ONE PARAGRAPH
#   If reports arrive independently at a roughly steady average rate,
#   monthly counts are approximately Poisson-distributed — and a
#   Poisson's variance equals its mean, so the standard deviation is
#   simply sqrt(mean). (Mean 185/month -> sd ~ sqrt(185) ~ 14; mean 900
#   -> sd ~ 30.) A month more than THREE standard deviations above the
#   average is very unlikely to be ordinary randomness
#   — so we draw a line there (the "upper control limit") and flag
#   whatever crosses it as worth a human's attention. This is the
#   classic "c-chart" from industrial quality control, and a standard
#   first tool in complaint trending.

library(dplyr)
library(tidyr)      # complete(): fill in missing months with zero
library(ggplot2)    # the plotting engine

# The four families we trend. "Other" (a handful of stray devices) and
# "Unknown" are excluded: control limits on near-zero series are noise.
TRENDED_FAMILIES <- c("Hip prosthesis", "Knee prosthesis",
                      "Bone plate", "Spinal fixation")


count_monthly <- function(events, families = TRENDED_FAMILIES) {
  # From one-row-per-report to one-row-per-family-per-month.
  #
  # THE SUBTLE, IMPORTANT PART: a month with zero reports produces NO
  # rows when you count — it's simply absent. Absent is not the same
  # as zero! A missing month would silently shorten the series and
  # bias every average upward. complete() builds the full grid of
  # (every family) x (every month from first to last) and fills the
  # holes with n = 0, so quiet months are honestly present.
  events |>
    filter(device_family %in% families, !is.na(year_month)) |>
    # year_month is text ("2020-07") because SQLite has no date type;
    # for a time axis we need a real Date, so we pin it to the 1st.
    mutate(month_date = as.Date(paste0(year_month, "-01"))) |>
    count(device_family, month_date, name = "n") |>
    complete(device_family,
             month_date = seq.Date(min(month_date), max(month_date),
                                   by = "month"),
             fill = list(n = 0))
}


add_control_limits <- function(monthly, k = 3) {
  # For each family: center line, standard deviation, and the two limits.
  #
  #   center = the family's average monthly count over the whole period
  #   sigma  = sqrt(center): the standard deviation for Poisson-like
  #            counts (variance = mean), i.e. the classic c-chart
  #   ucl    = upper control limit = center + k * sigma
  #   lcl    = lower control limit = center - k * sigma (floored at 0 —
  #            a count can't be negative)
  #
  # k = 3 ("three sigma") is the century-old industrial default: wide
  # enough that ordinary randomness almost never crosses it, so a
  # crossing means "investigate", not "panic".
  #
  # HONEST LIMITATION (also in the docs): the center is computed from
  # ALL months — so a big spike raises its own bar a little, making
  # these limits slightly conservative. Fancier versions use a rolling
  # baseline; that's a documented extension, not a hidden flaw.
  monthly |>
    group_by(device_family) |>
    mutate(
      center = mean(n),
      sigma  = sqrt(center),
      ucl    = center + k * sigma,
      lcl    = pmax(0, center - k * sigma),
      status = case_when(
        n > ucl ~ "above limit",     # unusually MANY reports
        n < lcl ~ "below limit",     # unusually FEW reports
        TRUE    ~ "within limits"
      )
    ) |>
    ungroup()
}


flagged_months <- function(monthly_limits) {
  # The month-by-month table a reviewer would actually read:
  # only the months that crossed a limit, most extreme first.
  monthly_limits |>
    filter(status != "within limits") |>
    mutate(distance = (n - center) / sigma) |>   # how many sd's out?
    arrange(desc(abs(distance))) |>
    select(device_family, month_date, n, center, ucl, lcl,
           status, distance)
}


plot_trends <- function(monthly_limits, ncol = 1) {
  # One panel per family: grey band = the "ordinary randomness" zone
  # between the limits; dashed line = the average; dots = actual
  # months, colored by status. A dot outside the band is a flag.
  ggplot(monthly_limits, aes(x = month_date, y = n)) +
    geom_ribbon(aes(ymin = lcl, ymax = ucl),
                fill = "grey88") +
    geom_line(aes(y = center), linetype = "dashed", color = "grey40") +
    geom_line(color = "steelblue4") +
    geom_point(aes(color = status), size = 1.6) +
    scale_color_manual(values = c("above limit"  = "red3",
                                  "below limit"  = "darkorange2",
                                  "within limits" = "grey30")) +
    facet_wrap(~ device_family, scales = "free_y", ncol = ncol) +
    labs(
      title = "Monthly adverse event reports with control limits",
      subtitle = "Grey band = expected range if reporting were steady; dots outside it are flagged",
      x = NULL, y = "reports per month", color = NULL,
      caption = "Report counts are not failure rates; flags mean 'investigate', not 'unsafe'."
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}


plot_trends_interactive <- function(monthly_limits) {
  # The interactive twin of plot_trends(): the SAME control chart, plus
  # what a browser adds — hover a dot for its exact numbers, drag a box
  # to zoom (double-click to reset), click legend entries to hide/show
  # a status group. Built by converting the ggplot with
  # plotly::ggplotly(): one chart definition, two outputs.
  #
  # Lives in its own function so the static path never depends on
  # plotly being installed. Requires: install.packages("plotly") once,
  # then renv::snapshot().
  requireNamespace("plotly", quietly = TRUE)

  df <- monthly_limits |>
    mutate(tooltip = sprintf(
      "%s\n%s\n%d reports (average %.0f)\n%s (%+.1f sd from average)",
      device_family, format(month_date, "%b %Y"), n, center,
      status, (n - center) / sigma
    ))

  # Mirrors plot_trends() with one addition: a text aesthetic carrying
  # the tooltip. ggplot itself doesn't know "text" (hence the
  # suppressWarnings); plotly picks it up as the hover box.
  p <- suppressWarnings(
    ggplot(df, aes(month_date, n)) +
      geom_ribbon(aes(ymin = lcl, ymax = ucl), fill = "grey88") +
      geom_line(aes(y = center), linetype = "dashed", color = "grey40") +
      geom_line(color = "steelblue4") +
      geom_point(aes(color = status, text = tooltip), size = 1.6) +
      scale_color_manual(values = c("above limit"   = "red3",
                                    "below limit"   = "darkorange2",
                                    "within limits" = "grey30")) +
      facet_wrap(~ device_family, scales = "free_y", ncol = 1) +
      labs(title = "Monthly reports with control limits (interactive)",
           x = NULL, y = "reports per month", color = NULL) +
      theme_minimal(base_size = 11)
  )

  plotly::ggplotly(p, tooltip = "text") |>
    plotly::config(displaylogo = FALSE)
}
