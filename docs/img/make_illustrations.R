# make_illustrations.R — generates the teaching figures used in docs/
# =====================================================================
# These are ILLUSTRATIONS: small, seeded, partly synthetic datasets
# drawn purely to explain concepts. They are deliberately separate from
# figures/ (which holds outputs computed from the real FDA data).
# Reproducible like everything else: run this file, get these PNGs.
#
#   Rscript docs/img/make_illustrations.R

library(dplyr)
library(tidyr)
library(ggplot2)

set.seed(42)   # fixed seed: same "random" numbers every run
dir.create("docs/img", showWarnings = FALSE)

theme_illus <- theme_minimal(base_size = 12) +
  theme(plot.title.position = "plot",
        legend.position = "none")

# ── 1. What a time series is (real bone-plate values, 2020) ──────────
ts_df <- tibble(
  month = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 10),
  n     = c(173, 181, 172, 134, 118, 185, 271, 431, 365, 271)
)
p1 <- ggplot(ts_df, aes(month, n)) +
  geom_line(color = "steelblue4") +
  geom_point(color = "steelblue4", size = 2.5) +
  geom_text(aes(label = n), vjust = -1, size = 3.4) +
  scale_x_date(date_labels = "%b\n2020", date_breaks = "1 month") +
  scale_y_continuous(limits = c(80, 480)) +
  labs(title = "A time series = one number per interval, kept in time order",
       subtitle = "The real bone-plate series, first 10 months: quantity = reports received, interval = one month",
       x = NULL, y = "reports received that month") +
  theme_illus
ggsave("docs/img/time_series_anatomy.png", p1, width = 8, height = 3.4, dpi = 150)

# ── 2. Absent is not zero ────────────────────────────────────────────
# Eleven months of ~100 reports; June truly had zero.
base <- tibble(
  month = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 12),
  n     = c(103, 97, 101, 99, 104, 0, 98, 102, 96, 100, 105, 99)
)
missing_view <- base |> filter(n > 0) |>
  mutate(view = sprintf("June silently ABSENT -> average pretends it never happened (mean = %.0f)",
                        mean(n)))
zero_view <- base |>
  mutate(view = sprintf("June honestly ZERO -> the dip is visible (mean = %.1f)",
                        mean(n)))
p2 <- bind_rows(missing_view, zero_view) |>
  group_by(view) |> mutate(m = mean(n)) |> ungroup() |>
  # factor with explicit levels: control the panel order (ABSENT on top),
  # instead of ggplot's default alphabetical ordering
  mutate(view = factor(view, levels = c(unique(missing_view$view),
                                        unique(zero_view$view)))) |>
  ggplot(aes(month, n)) +
  geom_line(color = "steelblue4") +
  geom_point(color = "steelblue4", size = 2) +
  geom_hline(aes(yintercept = m), linetype = "dashed", color = "grey40") +
  facet_wrap(~ view, ncol = 1) +
  labs(title = "Absent is not zero",
       subtitle = "The same year, two treatments of an empty June.\nDashed line = the average each view believes.",
       x = NULL, y = "reports per month") +
  theme_illus
ggsave("docs/img/absent_vs_zero.png", p2, width = 8, height = 4.6, dpi = 150)

# ── 3. The square-root rule: sigma = sqrt(mean) ──────────────────────
sq <- bind_rows(
  tibble(month = 1:36, n = rpois(36, 100),
         grp = "Small series: mean 100, so sd = sqrt(100) = 10, band 70-130"),
  tibble(month = 1:36, n = rpois(36, 900),
         grp = "Big series: mean 900, so sd = sqrt(900) = 30, band 810-990")
) |>
  group_by(grp) |>
  mutate(center = mean(n), sigma = sqrt(center),
         ucl = center + 3 * sigma, lcl = center - 3 * sigma) |>
  ungroup()
p3 <- ggplot(sq, aes(month, n)) +
  geom_ribbon(aes(ymin = lcl, ymax = ucl), fill = "grey88") +
  geom_line(aes(y = center), linetype = "dashed", color = "grey40") +
  geom_line(color = "steelblue4") +
  facet_wrap(~ grp, ncol = 1, scales = "free_y") +
  labs(title = "The square-root rule: standard deviation = sqrt(mean)",
       subtitle = "The big series moves more in absolute terms (+/-90 vs +/-30) but far less relative to its size.\nAnd the sd costs nothing to estimate: it comes straight from the mean.",
       x = "month", y = "count") +
  theme_illus
ggsave("docs/img/sqrt_rule.png", p3, width = 8, height = 4.6, dpi = 150)

# ── 4. The control chart, fully annotated ────────────────────────────
n <- rpois(36, 100)
n[9]  <- 55    # an injected dip  (below LCL)
n[24] <- 155   # an injected spike (above UCL)
cc <- tibble(month = seq.Date(as.Date("2021-01-01"), by = "month",
                              length.out = 36),
             n = n) |>
  mutate(center = mean(n), sigma = sqrt(center),
         ucl = center + 3 * sigma, lcl = center - 3 * sigma,
         status = case_when(n > ucl ~ "above", n < lcl ~ "below",
                            TRUE ~ "within"))
lab_x <- max(cc$month) + 65   # annotation column, right of the data
p4 <- ggplot(cc, aes(month, n)) +
  geom_ribbon(aes(ymin = lcl, ymax = ucl), fill = "grey88") +
  geom_line(aes(y = center), linetype = "dashed", color = "grey40") +
  geom_line(color = "steelblue4") +
  geom_point(aes(color = status), size = 2) +
  scale_color_manual(values = c(above = "red3", below = "darkorange2",
                                within = "grey30")) +
  annotate("text", x = lab_x, y = cc$ucl[1], hjust = 0, size = 3.4,
           label = "UCL = mean + 3 sd") +
  annotate("text", x = lab_x, y = cc$center[1], hjust = 0, size = 3.4,
           color = "grey35", label = "mean (center line)") +
  annotate("text", x = lab_x, y = cc$lcl[1], hjust = 0, size = 3.4,
           label = "LCL = mean - 3 sd") +
  annotate("text", x = lab_x, y = cc$center[1] - 1.7 * cc$sigma[1],
           hjust = 0, size = 3.2, color = "grey45",
           label = "grey band:\nordinary randomness\nlives in here") +
  annotate("text", x = cc$month[24], y = cc$n[24] + 9, size = 3.4,
           color = "red3", fontface = "bold",
           label = "outside the band:\nsignal - investigate") +
  annotate("text", x = cc$month[9], y = cc$n[9] - 9, size = 3.4,
           color = "darkorange2", fontface = "bold",
           label = "unusually FEW is\nalso a signal") +
  scale_x_date(limits = c(min(cc$month), max(cc$month) + 320),
               date_labels = "%Y", date_breaks = "1 year") +
  scale_y_continuous(limits = c(35, 175)) +
  labs(title = "Anatomy of a control chart (synthetic data)",
       subtitle = "A steady process, ~100 events/month, one injected spike and one dip.\nInside the grey band = ordinary randomness; the colored points are what 'flagged' means.",
       x = NULL, y = "count per month") +
  theme_illus
ggsave("docs/img/control_chart_anatomy.png", p4, width = 8.6, height = 4.6, dpi = 150)

cat("wrote:", paste(list.files("docs/img", pattern = "png$"), collapse = ", "), "\n")
