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

# ── 5. The 2x2 contingency table behind PRR/ROR (Phase 4) ────────────
cells <- tibble(
  x = c(1, 2, 1, 2),
  y = c(2, 2, 1, 1),
  cell = c("a", "b", "c", "d"),
  desc = c("family D reports\nWITH problem P",
           "family D reports\nWITHOUT problem P",
           "other families\nWITH problem P",
           "other families\nWITHOUT problem P")
)
p5 <- ggplot(cells, aes(x, y)) +
  geom_tile(fill = c("#fde0dd", "#e8e8e8", "#e8e8e8", "#e8e8e8"),
            color = "grey30", linewidth = 0.6, width = 0.97, height = 0.97) +
  geom_text(aes(label = cell), fontface = "bold", size = 10,
            nudge_y = 0.22) +
  geom_text(aes(label = desc), size = 3.4, nudge_y = -0.14,
            color = "grey25") +
  annotate("text", x = 1, y = 2.62, label = "problem P reported",
           size = 3.8, fontface = "bold") +
  annotate("text", x = 2, y = 2.62, label = "problem P not reported",
           size = 3.8, fontface = "bold") +
  annotate("text", x = 0.30, y = 2, label = "device\nfamily D",
           size = 3.8, fontface = "bold") +
  annotate("text", x = 0.30, y = 1, label = "all other\nfamilies",
           size = 3.8, fontface = "bold") +
  annotate("text", x = 1.5, y = 0.28, size = 3.9, label =
    "PRR = ( a / (a+b) )  /  ( c / (c+d) )     ROR = (a x d) / (b x c)") +
  annotate("text", x = 1.5, y = 0.06, size = 3.2, color = "grey35", label =
    "PRR: 'the share of D's reports that mention P, compared to everyone else's share'") +
  scale_x_continuous(limits = c(-0.15, 2.6)) +
  scale_y_continuous(limits = c(-0.1, 2.8)) +
  labs(title = "Every signal statistic starts from this 2x2 table",
       subtitle = "Count every report into exactly one cell; a is the cell under investigation.") +
  theme_void(base_size = 12) +
  theme(plot.title.position = "plot",
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30"))
ggsave("docs/img/contingency_2x2.png", p5, width = 7.6, height = 5.2, dpi = 150)
cat("2x2 diagram written\n")

# ── 6. The text-mining pipeline: narrative -> tokens -> counts (Phase 5)
steps <- tibble(
  y = c(4, 3, 2, 1),
  title = c("1. The narrative (raw text)",
            "2. Tokenize: chop into words, lowercased",
            "3. Remove stop words (filler + domain boilerplate)",
            "4. Count what remains"),
  body = c('"PT UNDERWENT REVISION SURGERY. METAL DEBRIS NOTED\nAROUND THE FEMORAL STEM. DEVICE RETURNED TO MFR."',
           "pt | underwent | revision | surgery | metal | debris |\nnoted | around | the | femoral | stem | device |\nreturned | to | mfr",
           "revision | surgery | metal | debris |\nfemoral | stem | returned",
           "metal: 1   debris: 1   revision: 1   surgery: 1\nfemoral: 1   stem: 1   returned: 1")
)
p6 <- ggplot(steps, aes(y = y)) +
  geom_rect(aes(xmin = 0, xmax = 10, ymin = y - 0.42, ymax = y + 0.42),
            fill = c("#fff3e0", "#e8f0f8", "#e8f0f8", "#e5f2e5"),
            color = "grey40", linewidth = 0.4) +
  geom_text(aes(x = 0.25, y = y + 0.28, label = title),
            hjust = 0, size = 3.9, fontface = "bold") +
  geom_text(aes(x = 0.25, y = y - 0.09, label = body),
            hjust = 0, size = 3.1, family = "mono", color = "grey20",
            lineheight = 1.0) +
  annotate("segment", x = 5, xend = 5, y = c(3.55, 2.55, 1.55),
           yend = c(3.45, 2.45, 1.45),
           arrow = arrow(length = unit(0.16, "cm")), color = "grey40") +
  scale_x_continuous(limits = c(0, 10)) +
  scale_y_continuous(limits = c(0.5, 4.6)) +
  labs(title = "From a report narrative to countable words",
       subtitle = "Counting is what computers do well; these three steps turn stories into something countable.\nNote what survives: the clinically meaningful words. Note what's gone: grammar, filler, boilerplate.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30"),
        plot.title.position = "plot")
ggsave("docs/img/text_mining_pipeline.png", p6, width = 8.4, height = 5.4, dpi = 150)
cat("text-mining pipeline diagram written\n")

# ── 7. Shiny reactivity: the spreadsheet-recalculation model (Phase 6)
boxes <- tibble(
  x = rep(c(1.4, 4.2, 7.0, 9.8), 2),
  y = rep(c(2.1, 0.7), each = 4),
  w = 2.5,
  title = c("User changes an input",
            "input$trend_families",
            "renderPlotly re-runs",
            "Browser updates",
            "User clicks a point",
            'event_data("plotly_click")',
            "renderDT re-runs",
            "Table appears"),
  body = c("un-ticks a family\ncheckbox",
           "the value updates;\neverything that READ it\nis now out of date",
           "filters the data,\nredraws the chart",
           "new chart, no page\nreload",
           "on the trends chart",
           "delivers the point's\ncustomdata:\n'Hip prosthesis|2020-08'",
           "parameterized SQL pulls\nthat month's reports",
           "drill-down below\nthe chart")
)
p7 <- ggplot(boxes) +
  geom_rect(aes(xmin = x - w/2, xmax = x + w/2,
                ymin = y - 0.42, ymax = y + 0.42),
            fill = rep(c("#fff3e0", "#e8f0f8", "#e8f0f8", "#e5f2e5"), 2),
            color = "grey40", linewidth = 0.4) +
  geom_text(aes(x = x, y = y + 0.26, label = title),
            size = 3.1, fontface = "bold") +
  geom_text(aes(x = x, y = y - 0.10, label = body),
            size = 2.6, color = "grey25", lineheight = 0.95) +
  annotate("segment",
           x    = rep(c(2.68, 5.48, 8.28), 2),
           xend = rep(c(2.92, 5.72, 8.52), 2),
           y    = rep(c(2.1, 0.7), each = 3),
           yend = rep(c(2.1, 0.7), each = 3),
           arrow = arrow(length = unit(0.16, "cm")), color = "grey40") +
  annotate("text", x = 0.15, y = 2.66, label = "Chain 1: an input changes",
           size = 3.0, fontface = "italic", color = "grey35", hjust = 0) +
  annotate("text", x = 0.15, y = 1.26, label = "Chain 2: a click lands",
           size = 3.0, fontface = "italic", color = "grey35", hjust = 0) +
  scale_x_continuous(limits = c(0, 11.2)) +
  scale_y_continuous(limits = c(0.1, 2.8)) +
  labs(title = "Shiny reactivity: outputs recompute when their inputs change",
       subtitle = "Exactly a spreadsheet: change cell A1 and every formula that reads A1 recalculates — automatically, and only those.\nTop chain: the family filter. Bottom chain: the click drill-down. Nothing polls, nothing refreshes; dependencies do the work.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/shiny_reactivity.png", p7, width = 9.6, height = 3.8, dpi = 150)
cat("shiny reactivity diagram written\n")

# ── 8. The pipeline: one command, every stage, tests as the gate (Phase 7)
pboxes <- tibble(
  x = c(1.2, 2.9, 4.6, 6.3, 6.3, 6.3, 8.0, 9.7),
  y = c(2.0, 2.0, 2.0, 3.0, 2.0, 1.0, 2.0, 2.0),
  label = c("fetch", "load", "clean", "trend", "signals", "terms",
            "test", "report"),
  sub = c("openFDA API\n(opt-in: long,\nneeds key)", "raw JSON\n-> raw_events",
          "-> clean_events\n(ledger printed)", "-> monthly_trends\n+ figures",
          "-> signal_stats\n+ figures", "-> narrative_terms\n+ figures",
          "50-test suite\n= the GATE", "Quarto renders\nfrom the db"),
  fill = c("#f5e6e6", rep("#e8f0f8", 5), "#e5f2e5", "#fff3e0")
)
p8 <- ggplot(pboxes) +
  geom_rect(aes(xmin = x - 0.75, xmax = x + 0.75, ymin = y - 0.40,
                ymax = y + 0.40), fill = pboxes$fill,
            color = "grey40", linewidth = 0.4) +
  geom_text(aes(x = x, y = y + 0.22, label = label),
            size = 3.6, fontface = "bold") +
  geom_text(aes(x = x, y = y - 0.10, label = sub),
            size = 2.5, color = "grey25", lineheight = 0.95) +
  annotate("segment",
           x    = c(1.95, 3.65, 5.35, 5.35, 5.35, 7.05, 7.05, 7.05, 8.75),
           xend = c(2.15, 3.85, 5.50, 5.50, 5.50, 7.22, 7.22, 7.22, 8.95),
           y    = c(2.0, 2.0, 2.33, 2.0, 1.67, 2.67, 2.0, 1.33, 2.0),
           yend = c(2.0, 2.0, 2.72, 2.0, 1.28, 2.30, 2.0, 1.70, 2.0),
           arrow = arrow(length = unit(0.15, "cm")), color = "grey40") +
  annotate("rect", xmin = 3.5, xmax = 7.3, ymin = 3.62, ymax = 4.28,
           fill = "#f0f0f0", color = "grey45", linetype = "dashed") +
  annotate("text", x = 5.4, y = 4.08, label = "pipeline/config.R",
           size = 3.3, fontface = "bold") +
  annotate("text", x = 5.4, y = 3.82, size = 2.6, color = "grey30",
           label = "families, thresholds, paths - settings live here, not in the stages") +
  annotate("segment", x = 5.4, xend = 5.4, y = 3.60, yend = 3.45,
           arrow = arrow(length = unit(0.14, "cm")), color = "grey45") +
  annotate("text", x = 1.2, y = 0.35, hjust = 0, size = 2.9,
           color = "grey35", fontface = "italic",
           label = "Rscript run_pipeline.R          (default: load -> ... -> test; fetch by name; report rendered separately)") +
  scale_x_continuous(limits = c(0.3, 10.6)) +
  scale_y_continuous(limits = c(0.1, 4.5)) +
  labs(title = "One command, every stage - and the test suite is the gate",
       subtitle = "Each stage is a callable function wrapping the engines you already built; the runner just walks the registry.\nA pipeline that ends by verifying its own math is a pipeline you can trust unattended.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/pipeline_diagram.png", p8, width = 9.8, height = 4.4, dpi = 150)
cat("pipeline diagram written\n")

# ── 9. Blocking: one R session is a single-lane bridge (Phase 8)
bl <- tibble(
  x = c(1.5, 4.0, 6.5, 9.0,   1.5, 4.0, 6.5, 9.0),
  y = c(rep(2.55, 4), rep(0.95, 4)),
  lab = c("click\n'Run stages'", "R runs the stage\n(terms: ~45 s)",
          "...browser WAITS\n(clicks queue up)", "done: log + timings\nappear, UI wakes",
          "click\n'Run stages'", "worker process\nruns the stage",
          "UI stays live\n(progress polls)", "result arrives\nwhen ready"),
  fill = c("#fff3e0", "#e8f0f8", "#f5e6e6", "#e5f2e5",
           "#fff3e0", "#e8f0f8", "#e5f2e5", "#e5f2e5")
)
p9 <- ggplot(bl) +
  geom_rect(aes(xmin = x - 1.05, xmax = x + 1.05, ymin = y - 0.38,
                ymax = y + 0.38), fill = bl$fill, color = "grey40",
            linewidth = 0.4) +
  geom_text(aes(x = x, y = y, label = lab), size = 2.9, lineheight = 0.95) +
  annotate("segment", x = c(2.6, 5.1, 7.6, 2.6, 5.1, 7.6),
           xend = c(2.9, 5.4, 7.9, 2.9, 5.4, 7.9),
           y = rep(c(2.55, 0.95), each = 3), yend = rep(c(2.55, 0.95), each = 3),
           arrow = arrow(length = unit(0.15, "cm")), color = "grey40") +
  annotate("text", x = 0.35, y = 3.3, hjust = 0, size = 3.2, fontface = "bold",
           label = "THIS APP (blocking): one session, one lane") +
  annotate("text", x = 0.35, y = 1.7, hjust = 0, size = 3.2, fontface = "bold",
           color = "grey45",
           label = "ROADMAP (background): future/promises add a second lane") +
  scale_x_continuous(limits = c(0.2, 10.4)) +
  scale_y_continuous(limits = c(0.4, 3.6)) +
  labs(title = "Why the browser freezes while a stage runs",
       subtitle = "A Shiny session is ONE R process - a single-lane bridge. While it computes, it cannot also serve clicks.\nHonest design for a local tool: show progress, say how long, keep the long fetch off the bridge entirely.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/blocking_single_lane.png", p9, width = 9.4, height = 3.6, dpi = 150)
cat("blocking diagram written\n")

# ── 10. Validate before the network (Phase 8b) ───────────────────────
vb <- tibble(
  x = c(1.4, 3.9, 6.4, 8.9),
  y = 1.6,
  lab = c("scope typed in\nfamilies, years,\nextra search term",
          "WHITELIST CHECK\nquery dictionary:\nfields the API knows",
          "PROBE (free look)\ncounts per slice,\nnothing saved",
          "FETCH\npages land in\ndata/raw/"),
  fill = c("#fff3e0", "#f5e6e6", "#e8f0f8", "#e5f2e5"))
p10 <- ggplot(vb) +
  geom_rect(aes(xmin = x - 1.1, xmax = x + 1.1, ymin = y - 0.55,
                ymax = y + 0.55), fill = vb$fill, color = "grey40",
            linewidth = 0.4) +
  geom_text(aes(x = x, y = y, label = lab), size = 3.0, lineheight = 1.0) +
  annotate("segment", x = c(2.55, 5.05, 7.55), xend = c(2.75, 5.25, 7.75),
           y = 1.6, yend = 1.6,
           arrow = arrow(length = unit(0.16, "cm")), color = "grey40") +
  annotate("text", x = 3.9, y = 0.62, size = 2.9, color = "#b30000",
           label = "unknown field / bad years -> refused HERE, in milliseconds, with a reason") +
  annotate("segment", x = 3.9, xend = 3.9, y = 0.78, yend = 1.02,
           arrow = arrow(length = unit(0.14, "cm"), ends = "first"),
           color = "#b30000", linetype = "dashed") +
  scale_x_continuous(limits = c(0.2, 10.1)) +
  scale_y_continuous(limits = c(0.3, 2.5)) +
  labs(title = "Validate before the network",
       subtitle = "The API only understands its own field names; a typo would fail as a silent zero-match download minutes later.\nSo the scope is checked against the query dictionary FIRST - errors are instant, informative, and free.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/validate_before_network.png", p10, width = 9.4, height = 2.9, dpi = 150)
cat("validation diagram written\n")

# ── 11. State vs ledger (Phase 8c) ───────────────────────────────────
sl <- tibble(
  x = c(2.3, 7.7), y = 2.05,
  lab = c("STATE\nthe five result tables\n(your account BALANCE:\nwhat things are now)",
          "LEDGER\nrun_history\n(your bank STATEMENT:\nevery event that made it so)"),
  fill = c("#e8f0f8", "#fff3e0"))
p11 <- ggplot(sl) +
  geom_rect(aes(xmin = x - 1.85, xmax = x + 1.85, ymin = y - 0.75,
                ymax = y + 0.75), fill = sl$fill, color = "grey40",
            linewidth = 0.4) +
  geom_text(aes(x = x, y = y, label = lab), size = 3.1, lineheight = 1.05) +
  annotate("rect", xmin = 3.6, xmax = 6.4, ymin = 3.32, ymax = 3.95,
           fill = "#e5f2e5", color = "grey40", linewidth = 0.4) +
  annotate("text", x = 5, y = 3.63, size = 3.1, lineheight = 1.0,
           label = "a run\n(fetch / pipeline / report)") +
  annotate("segment", x = 4.4, xend = 2.9, y = 3.28, yend = 2.9,
           arrow = arrow(length = unit(0.16, "cm")), color = "grey40") +
  annotate("segment", x = 5.6, xend = 7.1, y = 3.28, yend = 2.9,
           arrow = arrow(length = unit(0.16, "cm")), color = "grey40") +
  annotate("text", x = 2.9, y = 3.18, size = 2.7, color = "grey35",
           hjust = 1, label = "updates the state ") +
  annotate("text", x = 7.15, y = 3.18, size = 2.7, color = "grey35",
           hjust = 0, label = " appends one line (even failures)") +
  annotate("segment", x = 6.6, xend = 5.6, y = 1.05, yend = 0.62,
           arrow = arrow(length = unit(0.16, "cm")), color = "grey45",
           linetype = "dashed") +
  annotate("text", x = 5.0, y = 0.42, size = 2.9, color = "grey30",
           fontface = "italic",
           label = "provenance = reading the ledger's latest line:\n\"Results from: pipeline (load, clean, trend...) — ok, 2026-08-21 11:35\"") +
  scale_x_continuous(limits = c(0.2, 9.8)) +
  scale_y_continuous(limits = c(0.05, 4.3)) +
  labs(title = "State and ledger: what things are, and how they got that way",
       subtitle = "The dashboard shows state; the run history is the ledger; the provenance line connects them.\nRead-only queries are deliberately not recorded - a ledger spammed by every glance is noise, not history.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/state_vs_ledger.png", p11, width = 9.2, height = 4.1, dpi = 150)
cat("state-vs-ledger diagram written\n")

# ── 12. One table, many vintages (Phase 8d) ──────────────────────────
vt <- tibble(
  x = 5, y = c(2.9, 2.1, 1.3),
  lab = c("run_20260821_1500   ← latest (the default view)",
          "run_20260821_1030",
          "legacy   (pre-versioning rows, migrated, ages out first)"),
  fill = c("#e5f2e5", "#e8f0f8", "#f0f0f0"))
p12 <- ggplot(vt) +
  annotate("rect", xmin = 0.8, xmax = 9.2, ymin = 0.75, ymax = 3.75,
           fill = NA, color = "grey30", linewidth = 0.6) +
  annotate("text", x = 1.0, y = 3.52, hjust = 0, size = 3.4,
           fontface = "bold", label = "monthly_trends  (one table)") +
  geom_rect(aes(xmin = 1.2, xmax = 8.8, ymin = y - 0.32, ymax = y + 0.32),
            fill = vt$fill, color = "grey45", linewidth = 0.35) +
  geom_text(aes(x = 1.45, y = y, label = lab), hjust = 0, size = 3.0) +
  annotate("text", x = 9.55, y = 2.9, hjust = 0, size = 2.8, color = "grey35",
           label = "read_result(con, name)\n= latest vintage,\nold schema, no run_id") +
  annotate("text", x = 9.55, y = 1.7, hjust = 0, size = 2.8, color = "grey35",
           label = "run selector\n= any vintage,\nsame charts") +
  annotate("segment", x = 9.45, xend = 8.9, y = c(2.9, 1.7), yend = c(2.9, 1.9),
           arrow = arrow(length = unit(0.14, "cm"), ends = "last"), color = "grey45") +
  annotate("text", x = 5, y = 0.35, size = 2.9, color = "grey30", fontface = "italic",
           label = "each pipeline run APPENDS its labeled rows; retention keeps the newest N; nothing is silently overwritten again") +
  scale_x_continuous(limits = c(0.5, 12.6)) +
  scale_y_continuous(limits = c(0.1, 4.1)) +
  labs(title = "Versioned results: one table, many vintages",
       subtitle = "A wine rack, not a whiteboard: runs add labeled bottles instead of wiping yesterday to write today.\nEvent tables (84K rows) stay unversioned by choice - drill-downs always query current events; documented, not hidden.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "grey30", size = 9.5),
        plot.title.position = "plot")
ggsave("docs/img/one_table_many_vintages.png", p12, width = 9.6, height = 3.9, dpi = 150)
cat("vintages diagram written\n")
