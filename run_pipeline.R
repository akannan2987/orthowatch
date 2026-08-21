#!/usr/bin/env Rscript
# run_pipeline.R — the whole project, one command
# =================================================
#   Rscript run_pipeline.R                # default: load -> ... -> test
#   Rscript run_pipeline.R clean trend    # just the named stages
#   Rscript run_pipeline.R probe          # ask the API what a fetch would get
#   Rscript run_pipeline.R all            # fetch -> ... -> test (long; API key)
#
# This file is deliberately thin: parse which stages, run them in
# canonical order with timing, print the summary, exit non-zero on any
# failure. All actual work lives in pipeline/stages.R as functions —
# so the same stages are callable from tests, from a scheduler, or
# from an app. Runners wrap pipelines; they don't contain them.

suppressPackageStartupMessages({
  library(DBI); library(RSQLite)
  library(dplyr); library(tibble); library(tidyr); library(stringr)
  library(lubridate); library(tidytext); library(ggplot2)
})

source("R/clean_events.R")
source("R/trending.R")
source("R/signal_detection.R")
source("R/text_mining.R")
source("R/run_history.R")
source("pipeline/config.R")
source("pipeline/stages.R")

args <- commandArgs(trailingOnly = TRUE)
# (Sequential ifs, not if/else across lines: at a script's TOP LEVEL,
# R considers `if (...) x` complete at the line break and chokes on a
# dangling `else` — a classic gotcha that only bites outside braces.)
wanted <- args
if (length(args) == 0)      wanted <- DEFAULT_STAGES
if (identical(args, "all")) wanted <- setdiff(names(PIPELINE_STAGES), "probe")

unknown <- setdiff(wanted, names(PIPELINE_STAGES))
if (length(unknown) > 0)
  stop("unknown stage(s): ", paste(unknown, collapse = ", "),
       "\nknown: ", paste(names(PIPELINE_STAGES), collapse = ", "))

# Run in canonical order regardless of how the user typed them.
wanted <- names(PIPELINE_STAGES)[names(PIPELINE_STAGES) %in% wanted]

cfg <- pipeline_config()
message("== OrthoWatch pipeline ==  stages: ", paste(wanted, collapse = " -> "))

timings <- data.frame(stage = character(), seconds = numeric())
run_ok <- TRUE
tryCatch({
  for (s in wanted) {
    message("\n── stage: ", s, " ──")
    t0 <- Sys.time()
    PIPELINE_STAGES[[s]](cfg)        # any error stops the whole run
    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    timings <- rbind(timings, data.frame(stage = s, seconds = secs))
  }
}, error = function(e) {
  run_ok <<- FALSE
  # An honest ledger keeps its bad days - record, then still fail loudly.
  try(record_run(cfg$db_path, "pipeline", paste(wanted, collapse = ", "),
                 "error", summary = conditionMessage(e)), silent = TRUE)
  stop(e)
})

record_run(cfg$db_path, "pipeline", paste(wanted, collapse = ", "), "ok",
           summary = paste(timings$stage, timings$seconds, collapse = "; "),
           seconds = sum(timings$seconds))
message("\n== pipeline complete ==")
print(timings, row.names = FALSE)
