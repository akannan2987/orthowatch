# config.R — the pipeline's settings panel
# ==========================================
# Every tunable number the pipeline uses lives HERE, in one place —
# never scattered through the stages. Change a threshold, rerun, done:
# configuration is data, code is machinery, and keeping them apart is
# what makes the machinery reusable. (Phase 8's app will read this
# same config — one settings panel, many consumers.)
#
# The FETCH scope (which device families, which years to download) is
# the one setting that lives elsewhere: in ingest/fetch_maude.py's
# CONFIGURATION block, next to the API code it drives. Stated here so
# nobody hunts for it.

pipeline_config <- function() {
  list(
    # ── where things live ────────────────────────────────────────────
    db_path         = "data/processed/orthowatch.db",
    figures_dir     = "figures",
    interactive_dir = "docs/interactive",   # published charts (Pages)

    # ── the analysis scope ───────────────────────────────────────────
    families = c("Hip prosthesis", "Knee prosthesis",
                 "Bone plate", "Spinal fixation"),

    # ── Phase 4 thresholds (documented judgments, tunable) ───────────
    min_a             = 3,     # Evans floor: >= 3 reports per pair
    min_problem_total = 30,    # drop problems mentioned < 30x overall
    top_n_signals     = 5,     # per family, in the forest plot

    # ── Phase 5 threshold ────────────────────────────────────────────
    min_total_terms   = 50,    # drop words with < 50 total mentions

    # ── fetch scope (NULL = the script's own config-block defaults) ──
    # Threaded through stage_probe/stage_fetch as CLI arguments; the
    # script validates everything again before any network call.
    fetch_families  = NULL,   # subset of family slugs, e.g. c("hip_prosthesis")
    fetch_year_from = NULL,   # e.g. 2023
    fetch_year_to   = NULL,   # e.g. 2024
    fetch_search    = "",     # extra clause, fields from the query dictionary

    # ── behavior ─────────────────────────────────────────────────────
    publish_interactive = TRUE,  # copy interactive HTML to docs/ (Pages)
    keep_runs = 10,              # result-table vintages retained per table

    # ── analysis scope (NULL = everything: all families, all years) ──
    # THE scope a run computes over. Set these and the run's vintage
    # contains ONLY that slice - selecting it in the app shows exactly
    # what was analyzed, nothing else.
    analysis_families  = NULL,   # e.g. c("Spinal fixation")
    analysis_year_from = NULL,   # e.g. "2024"
    analysis_year_to   = NULL    # e.g. "2024"
  )
}
