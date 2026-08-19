# 04_text_mining.R — Phase 5: the narratives get their say
# ===========================================================
# Run LINE BY LINE alongside docs/06-phase-5-text-mining.md.
#
# The story: Phases 3-4 worked entirely from categorical fields. But
# the richest part of every report is its free-text narrative — and
# our earlier findings left two open questions only the text can
# answer:
#   Mission A: the 26,093 reports coded with the vague "unidentified
#              problem" — do their STORIES contain specifics the CODE
#              omits?
#   Mission B: spinal fixation's odd "No Apparent Adverse Event"
#              signal (PRR 7.8) — do the narratives read like real
#              events, or like one reporter's filing habit?

library(DBI)
library(RSQLite)
library(dplyr)
library(tibble)
library(tidyr)
library(stringr)
library(tidytext)
library(ggplot2)

source("R/text_mining.R")   # tokenize_narratives(), count_terms(),
                            # distinctive_terms(), the two plots

con <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")


# ── 1. Pull narratives and take their measure ────────────────────────

events <- dbGetQuery(con, "
  SELECT report_number, device_family, product_problems, narrative
  FROM clean_events
  WHERE device_family IN ('Hip prosthesis', 'Knee prosthesis',
                          'Bone plate', 'Spinal fixation')
") |> as_tibble()

# How much text is there, and who leaves it blank?
events |>
  group_by(device_family) |>
  summarise(
    reports        = n(),
    with_narrative = sum(!is.na(narrative) & narrative != ""),
    pct_with_text  = round(100 * with_narrative / reports, 1),
    median_chars   = median(nchar(narrative), na.rm = TRUE)
  )


# ── 2. Tokenize (the heavy step: ~a minute, some RAM) ────────────────

tokens <- tokenize_narratives(events)
nrow(tokens)                     # millions — one row per surviving word
n_distinct(tokens$word)

# Housekeeping: the raw narratives served their purpose; free the RAM.
events_meta <- events |> select(report_number, device_family, product_problems)
rm(events); gc()

# The most common surviving words overall — read them once. Expect
# clinical/procedural vocabulary; if you see filler dominating, the
# stop-word lists need work.
tokens |> count(word, sort = TRUE) |> head(15)


# ── 3. Each family's distinctive vocabulary ──────────────────────────

term_counts <- count_terms(tokens)
dist <- distinctive_terms(term_counts)     # min_total = 50 by default

dist |>
  group_by(device_family) |>
  slice_max(log2_ratio, n = 8) |>
  ungroup() |>
  select(device_family, word, n, per_10k, ratio, log2_ratio)

# Sanity questions while reading (your judgment step):
#  * Anatomy check: do the words fit the family? (femoral/acetabular
#    for hips, tibial for knees, pedicle/rods for spine would all be
#    textbook.)
#  * Do any Phase 4 signals reappear as words? (Corrosion vocabulary
#    for hips would corroborate the coded signal from the text side.)
#  * Any words that look like one reporter's template rather than
#    clinical content?


# ── 4. Figures: static headline + the interactive scatter ───────────

p_terms <- plot_distinctive_terms(dist)
p_terms
dir.create("figures", showWarnings = FALSE)
ggsave("figures/terms_by_family.png", p_terms,
       width = 10, height = 7, dpi = 150)

# Interactive — where hover genuinely earns it: hundreds of words, all
# labeled on demand. Dots far BELOW the diagonal are that family's own
# vocabulary. Preview -> figures/ (ignored); publish -> docs/interactive/.
library(plotly)
ip_terms <- plot_term_scatter_interactive(dist)
ip_terms
htmlwidgets::saveWidget(ip_terms, "figures/narrative_terms.html",
                        selfcontained = TRUE)
file.copy("figures/narrative_terms.html",
          "docs/interactive/narrative_terms.html", overwrite = TRUE)


# ── 5. MISSION A: what do the "unidentified problem" reports say? ────
# Split every tokenized report by whether its CODES were vague-only,
# then compare vocabularies. If the vague reports' words look just as
# clinical as everyone else's, the stories contain what the codes omit.

VAGUE <- "Adverse Event Without Identified Device or Use Problem"

vague_ids <- events_meta |>
  filter(str_detect(product_problems, fixed(VAGUE)),
         # vague-ONLY: no other code alongside it
         product_problems == VAGUE) |>
  pull(report_number)
length(vague_ids)

tokens_grouped <- tokens |>
  mutate(coding = if_else(report_number %in% vague_ids,
                          "vague-only code", "specific code(s)"))

# Compare: the vague-only group's most-used words vs the others'.
mission_a <- tokens_grouped |>
  count(coding, word, name = "n") |>
  group_by(coding) |>
  mutate(per_10k = 1e4 * n / sum(n)) |>
  slice_max(per_10k, n = 15) |>
  ungroup()
mission_a |> pivot_wider(id_cols = word, names_from = coding,
                         values_from = per_10k) |> print(n = 25)

# And read three of them yourself — sampled, truncated. Counting
# guides; reading decides.
set.seed(1)
con2 <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")
samp <- dbGetQuery(con2, sprintf(
  "SELECT narrative FROM clean_events WHERE report_number IN ('%s')",
  paste(sample(vague_ids, 3), collapse = "','")))
dbDisconnect(con2)
cat(str_trunc(samp$narrative, 500), sep = "\n\n---\n\n")


# ── 6. MISSION B: the spinal "No Apparent Adverse Event" reports ─────

naae_ids <- events_meta |>
  filter(device_family == "Spinal fixation",
         str_detect(product_problems, fixed("No Apparent Adverse Event"))) |>
  pull(report_number)
length(naae_ids)      # expect ~141, matching the Phase 4 signal's a

# Their vocabulary vs. the rest of spinal fixation's:
tokens |>
  filter(device_family == "Spinal fixation") |>
  mutate(grp = if_else(report_number %in% naae_ids,
                       "NAAE-coded", "other spinal")) |>
  count(grp, word) |>
  group_by(grp) |>
  mutate(per_10k = 1e4 * n / sum(n)) |>
  slice_max(per_10k, n = 12) |>
  ungroup() |>
  pivot_wider(id_cols = word, names_from = grp, values_from = per_10k) |>
  print(n = 20)

# Read three:
set.seed(2)
con2 <- dbConnect(RSQLite::SQLite(), "data/processed/orthowatch.db")
samp <- dbGetQuery(con2, sprintf(
  "SELECT narrative FROM clean_events WHERE report_number IN ('%s')",
  paste(sample(naae_ids, 3), collapse = "','")))
dbDisconnect(con2)
cat(str_trunc(samp$narrative, 500), sep = "\n\n---\n\n")

# Identical template openings across these narratives = your Phase 4
# reporter-habit hypothesis, confirmed from the text side. Genuinely
# varied clinical stories = hypothesis weakened. Your call — verdict
# comment at the bottom either way.


# ── 7. Write the term statistics into the cabinet ────────────────────

dbWriteTable(con, "narrative_terms",
             dist |> select(device_family, word, n, per_10k,
                            ratio, log2_ratio),
             overwrite = TRUE)
dbListTables(con)
# expect: clean_events, monthly_trends, narrative_terms, raw_events, signal_stats

dbDisconnect(con)


# ── Text-mining verdict (2026-08-19, AK) ─────────────────────────────
# Distinctive vocabularies revealed subpopulations the codes hid: the
# "bone plate" family contains a large craniofacial/mandibular plating
# subgroup (mandible, retrognathia, sternal, resorbable-plate brands),
# and hip narratives orbit metal-on-metal resurfacing (top term "bhr",
# 4,081 mentions) — the text-side counterpart of Phase 4's metal-
# degradation signal cluster.
# MISSION A (corrected scope): the vague code has 26,093 mentions but
# only 227 vague-ONLY reports. Those 227 skew to hip revision language
# (hip, revision, pain, cobalt) with litigation markers ("US LEGAL
# MDL") and LACK standard investigation boilerplate — largely a
# litigation-channel metal-ion genre, mixed with information-poor
# not-returned filings. The stories do contain specifics the codes
# omit, but the code is usually an add-on, not a void.
# MISSION B: CONFIRMED — the spinal "No Apparent Adverse Event" signal
# (141 reports) is a reporting artifact: filing vocabulary (medwatch,
# lot, filed) instead of clinical vocabulary, and sampled narratives
# opening with one manufacturer's identical 21 CFR 803 legal-disclaimer
# template, several literature/journal-review sourced. A reporter-
# habit pattern, not a device pattern — closing the caveat opened in
# the Phase 4 verdict.
# Narrative words are leads from unverified reporter text, never
# findings about devices.
