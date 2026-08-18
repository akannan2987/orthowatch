# clean_events.R — Phase 2: the cleaning engine
# ================================================
# Reusable functions that turn raw_events into clean_events.
#
# WHY THIS FILE LIVES IN R/ AND NOT IN analysis/:
#   analysis/ holds scripts you RUN (narratives with a beginning and end).
#   R/ holds functions you CALL (tools, usable from scripts, the Shiny
#   app, the Quarto report, and — later — unit tests). Keeping the logic
#   here means every part of the project cleans data the exact same way.
#
# HOW TO USE:
#   source("R/clean_events.R")   # loads these functions into your session
#   clean <- clean_events(raw_df)
#
# Every function does ONE job and says why it exists. Cleaning rules are
# deliberately visible and boring — in regulated analytics, a clever
# hidden fix is worse than an obvious documented one.

library(dplyr)      # data manipulation verbs: mutate, filter, distinct...
library(stringr)    # string helpers: str_detect, str_squish...
library(lubridate)  # date parsing: ymd(), floor_date()...


# ── 1. Dates ─────────────────────────────────────────────────────────

parse_maude_dates <- function(df) {
  # MAUDE dates arrive as "YYYYMMDD" strings (e.g. "20230415").
  # lubridate::ymd() turns them into real Date objects; anything
  # unparseable becomes NA (R's "missing value") with a warning —
  # we count those NAs in the ledger instead of hiding them.
  #
  # We also pre-compute two convenience columns:
  #   date_received_iso : "2023-04-15" — ISO-8601 text. SQLite has no
  #                       real date type, but ISO strings sort correctly,
  #                       which is all SQL needs for filtering/grouping.
  #   year_month        : "2023-04" — the trending unit for Phase 3.
  df |>
    mutate(
      date_received_parsed = suppressWarnings(ymd(date_received)),
      date_of_event_parsed = suppressWarnings(ymd(date_of_event)),
      date_received_iso    = format(date_received_parsed, "%Y-%m-%d"),
      year_month           = format(date_received_parsed, "%Y-%m")
    )
}


# ── 2. Device names ──────────────────────────────────────────────────

standardize_generic_name <- function(x) {
  # The raw field contains the same concept spelled many ways:
  #   "PLATE,FIXATION,BONE"    (no spaces after commas)
  #   "PLATE, FIXATION, BONE"  (spaces after commas)
  #   "PATELLO/FEMOROTIBIAL" vs "PATELLOFEMOROTIBIAL"
  # We normalize the FORMATTING (case, whitespace, comma spacing,
  # stray slashes) without changing the WORDS — formatting fixes are
  # safe; rewriting words risks merging genuinely different devices.
  x |>
    str_to_upper() |>                       # one consistent case
    str_squish() |>                         # trim + collapse doubled spaces
    str_replace_all(",\\s*", ", ") |>       # exactly one space after commas
                                            # (\\s* = "any amount of
                                            #  whitespace" in regex)
    str_replace_all("/", "")                # PATELLO/FEMORO... -> PATELLOFEMORO...
}

classify_device_family <- function(generic_name_std) {
  # THE key harmonization step: collapse hundreds of spelling variants
  # into five analysis-ready families. All downstream work (trending,
  # signal detection, the dashboard) groups by this column.
  #
  # case_when() reads top-down and stops at the first TRUE — so order
  # matters. str_detect(x, "HIP") asks "does the string contain HIP?".
  # Anything matching no rule lands in "Other", which we INSPECT rather
  # than delete: a big Other bucket means the rules need work.
  case_when(
    str_detect(generic_name_std, "PROSTHESIS") &
      str_detect(generic_name_std, "HIP")   ~ "Hip prosthesis",
    str_detect(generic_name_std, "PROSTHESIS") &
      str_detect(generic_name_std, "KNEE")  ~ "Knee prosthesis",
    str_detect(generic_name_std, "PLATE") &
      str_detect(generic_name_std, "BONE")  ~ "Bone plate",
    str_detect(generic_name_std, "SPINAL|SPINE") ~ "Spinal fixation",
    is.na(generic_name_std)                 ~ "Unknown",
    TRUE                                    ~ "Other"
  )
}


# ── 3. Event types ───────────────────────────────────────────────────

clean_event_type <- function(x) {
  # The raw field contains Death / Injury / Malfunction / Other — plus
  # blanks and NAs (your load summary showed 5 of them). Blanks become
  # an explicit "Unknown": never silently drop rows, and never leave
  # two kinds of "missing" ("" vs NA) for later code to trip over.
  x_clean <- str_squish(x)
  if_else(is.na(x_clean) | x_clean == "", "Unknown", x_clean)
}


# ── 4. Duplicates ────────────────────────────────────────────────────

dedupe_reports <- function(df) {
  # Rule: one row per report_number, keeping the most recently received
  # version (MAUDE issues follow-ups; latest = most complete).
  #
  # SUBTLE TRAP, worth learning once: distinct() treats all NAs as the
  # SAME value — so if several reports have a missing report_number,
  # naive deduplication would collapse them into one row and silently
  # destroy data. Fix: set the missing-ID rows aside, dedupe the rest,
  # and bind the two parts back together.
  no_id <- df |> filter(is.na(report_number))
  with_id <- df |>
    filter(!is.na(report_number)) |>
    arrange(desc(date_received)) |>              # newest first...
    distinct(report_number, .keep_all = TRUE)    # ...keep first seen
  bind_rows(with_id, no_id)
}


# ── 5. The orchestrator ──────────────────────────────────────────────

clean_events <- function(raw_df, verbose = TRUE) {
  # Runs the whole cleaning pipeline in a fixed, documented order and
  # prints a "cleaning ledger": row counts and NA counts at each step,
  # so every change to the data is announced, never silent.
  ledger <- function(msg, df) {
    if (verbose) message(sprintf("%-46s %8s rows", msg,
                                 format(nrow(df), big.mark = ",")))
    df
  }

  out <- raw_df |>
    ledger("raw input", df = _) |>
    parse_maude_dates() |>
    mutate(
      generic_name_std = standardize_generic_name(generic_name),
      device_family    = classify_device_family(generic_name_std),
      event_type_clean = clean_event_type(event_type),
      manufacturer_std = str_squish(str_to_upper(manufacturer_name))
    ) |>
    ledger("after parsing + standardizing", df = _) |>
    dedupe_reports() |>
    ledger("after deduplication", df = _)

  if (verbose) {
    n_bad_dates <- sum(is.na(out$date_received_parsed))
    message(sprintf("%-46s %8s rows", "unparseable date_received (kept, NA)",
                    format(n_bad_dates, big.mark = ",")))
    message("device_family counts:")
    print(count(out, device_family, sort = TRUE))
  }
  out
}
