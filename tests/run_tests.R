# run_tests.R — the project's test runner
# =========================================
# Runs every automated test in tests/testthat/.
#
#   From the Terminal (project root):   Rscript tests/run_tests.R
#   From the R Console:                 source("tests/run_tests.R")
#
# Why tests exist: the smoke checks we ran by hand while building each
# engine are now written down and re-runnable forever. Any future edit
# that silently breaks the math turns the run red. Green = every claim
# these files make about the engines still holds.

library(testthat)

# Make the engines available to the tests:
source("R/clean_events.R")
source("R/trending.R")
source("R/signal_detection.R")
source("R/text_mining.R")
source("pipeline/config.R")
source("pipeline/stages.R")

# Run everything; stop_on_failure makes Rscript exit non-zero on any
# failure (so automation — a future CI step — can notice).
test_dir("tests/testthat", stop_on_failure = TRUE)
