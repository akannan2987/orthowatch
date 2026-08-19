# text_mining.R — Phase 5: the text mining engine
# ==================================================
# The categorical fields have had their say (Phases 3-4). This engine
# lets the free-text NARRATIVES speak: chop them into countable words,
# strip the filler, and find which words are over-represented in one
# device family's stories versus everyone else's.
#
# THE IDEA IN ONE PARAGRAPH
#   Computers can't read stories, but they can count words — and
#   counting is enough for the surveillance question. After
#   tokenizing (splitting text into lowercase words) and removing
#   stop words (filler like "the", plus domain boilerplate like
#   "patient"), we ask, for every word w and family D, EXACTLY the
#   Phase 4 question with words in place of problem codes:
#     "does w take up a larger share of D's narrative words than of
#      everyone else's?"
#   Same 2x2 logic, same rate-ratio arithmetic, same Haldane-style
#   smoothing against zeros. One statistical idea, two phases.

library(dplyr)
library(tidyr)
library(stringr)
library(tidytext)    # unnest_tokens() + the standard stop_words list
library(ggplot2)

TM_FAMILIES <- c("Hip prosthesis", "Knee prosthesis",
                 "Bone plate", "Spinal fixation")

# Domain stop words: near-universal MDR boilerplate that clutters
# frequency views without distinguishing anything. Kept SHORT on
# purpose — the rate-ratio statistic already downweights words that
# appear everywhere; this list only declutters. A judgment, stated.
DOMAIN_STOP <- c("patient", "device", "report", "reported", "reportedly",
                 "information", "mdr", "manufacturer", "stated", "noted",
                 "received", "product", "medical", "additional", "evaluation")


tokenize_narratives <- function(events_text) {
  # events_text: tibble with report_number, device_family, narrative.
  # Returns one row per (report, word): lowercased, filler removed,
  # pure numbers removed, very short fragments removed.
  #
  # Memory note: 84K narratives explode into millions of token rows —
  # expect the tokenize step to take a minute and some RAM. The
  # analysis script keeps only needed columns and cleans up after.
  events_text |>
    filter(!is.na(narrative), narrative != "") |>
    unnest_tokens(word, narrative) |>            # the chopping step
    anti_join(tidytext::stop_words, by = "word") |>  # standard filler out
    filter(!word %in% DOMAIN_STOP,               # domain boilerplate out
           !str_detect(word, "^[0-9]+$"),        # bare numbers out
           str_length(word) >= 3)                # fragments out
}


count_terms <- function(tokens) {
  # Word counts per family, plus each family's total word count —
  # the denominators, exactly as family report totals were in Phase 4.
  tokens |>
    filter(device_family %in% TM_FAMILIES) |>
    count(device_family, word, name = "n") |>
    group_by(device_family) |>
    mutate(family_total = sum(n)) |>
    ungroup()
}


distinctive_terms <- function(term_counts, min_total = 50) {
  # For every (family, word): the word's rate in that family's
  # narratives vs. its rate in everyone else's — a rate ratio, i.e.
  # PRR arithmetic applied to words. +0.5/+1 smoothing keeps zero
  # counts from producing 0 or Inf (the Haldane idea again).
  #
  #   rate_family = (n + 0.5) / (family_total + 1)
  #   rate_others = (n_others + 0.5) / (others_total + 1)
  #   ratio       = rate_family / rate_others;  log2_ratio = log2(ratio)
  #
  # log2 makes the scale symmetric and readable: +1 = twice the rate,
  # +3 = eight times, -1 = half.
  totals <- term_counts |> distinct(device_family, family_total)
  grand_total <- sum(totals$family_total)

  term_counts |>
    group_by(word) |>
    mutate(word_total = sum(n)) |>
    ungroup() |>
    filter(word_total >= min_total) |>           # rare-word noise out
    mutate(
      n_others      = word_total - n,
      others_total  = grand_total - family_total,
      rate_family   = (n + 0.5) / (family_total + 1),
      rate_others   = (n_others + 0.5) / (others_total + 1),
      ratio         = rate_family / rate_others,
      log2_ratio    = log2(ratio),
      per_10k       = 1e4 * n / family_total     # human-readable rate
    ) |>
    arrange(desc(log2_ratio))
}


plot_distinctive_terms <- function(dist, top_n = 12) {
  # Static headline figure: each family's most distinctive narrative
  # words, ranked by log2 rate ratio. Read a bar as "this word occurs
  # 2^x times as often in this family's stories as in the others'".
  top <- dist |>
    group_by(device_family) |>
    slice_max(log2_ratio, n = top_n) |>
    ungroup()

  ggplot(top, aes(x = log2_ratio,
                  y = reorder_within(word, log2_ratio, device_family))) +
    geom_col(fill = "steelblue4") +
    scale_y_reordered() +
    facet_wrap(~ device_family, scales = "free_y", ncol = 2) +
    labs(
      title = "Most distinctive narrative words per device family",
      subtitle = "log2 rate ratio: +1 = word occurs twice as often in this family's narratives as in the others', +3 = eight times",
      x = "log2 rate ratio (family vs. all others)", y = NULL,
      caption = "Words from unverified reporter narratives; distinctive wording is a lead, not a finding."
    ) +
    theme_minimal(base_size = 11)
}


plot_term_scatter_interactive <- function(dist, min_per_10k = 1) {
  # The interactive earns its keep here for a concrete reason: this
  # scatter has hundreds of points, and a static version could label
  # only a handful before turning into ink soup. Hover labels ALL of
  # them: each dot is a word, x = its rate in the family, y = its rate
  # everywhere else (both per 10,000 words, log scales). Dots far
  # BELOW the diagonal are that family's vocabulary. Phase 6's
  # dashboard calls this function directly.
  requireNamespace("plotly", quietly = TRUE)

  d <- dist |>
    filter(per_10k >= min_per_10k) |>
    mutate(
      # smoothed rate for the axis: words absent elsewhere would sit at
      # zero, which a log axis cannot draw — smoothing floors them at a
      # small visible value instead of silently dropping them (and
      # "this family's word, absent everywhere else" is exactly the
      # most interesting kind of dot to keep)
      rate_others_10k = 1e4 * (n_others + 0.5) / (others_total + 1),
      tooltip = sprintf(
        "%s\n\"%s\"\n%.1f per 10k words here vs %.2f elsewhere\nratio %.1fx  (n = %d)",
        device_family, word, per_10k, rate_others_10k, ratio, n)
    )

  p <- suppressWarnings(
    ggplot(d, aes(x = per_10k, y = rate_others_10k)) +
      geom_abline(slope = 1, intercept = 0,
                  linetype = "dashed", color = "grey50") +
      geom_point(aes(text = tooltip), alpha = 0.45,
                 color = "steelblue4", size = 1.3) +
      scale_x_log10() + scale_y_log10() +
      facet_wrap(~ device_family, ncol = 2) +
      labs(title = "Narrative vocabulary, family vs. everyone else (interactive)",
           x = "occurrences per 10,000 words in this family",
           y = "per 10,000 words in all other families") +
      theme_minimal(base_size = 11)
  )
  plotly::ggplotly(p, tooltip = "text") |>
    plotly::config(displaylogo = FALSE)
}
