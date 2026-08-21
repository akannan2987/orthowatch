# stages.R — the pipeline's stages, each a callable function
# ============================================================
# THE DESIGN RULE THIS FILE EMBODIES
#   A capability that only exists inside a script (or behind a button)
#   can only be run by a human. Wrapped as a FUNCTION taking a config,
#   it can be run by the runner, by tests, by a scheduler, by Phase
#   8's app — by anything. UIs and runners should WRAP a pipeline,
#   never contain one.
#
# Every stage: takes the config, does one job, prints a one-line
# status, and returns (invisibly) a small summary the runner collects
# into the final timing table. Stages assume the engines are sourced
# (the runner and the test suite both do that).

`%||%` <- function(a, b) if (is.null(a)) b else a

.stage_msg <- function(...) message(sprintf(...))

.with_db <- function(cfg, f) {
  # Open, do the work, ALWAYS close — even if the work errors.
  con <- DBI::dbConnect(RSQLite::SQLite(), cfg$db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  f(con)
}

.python <- function() {
  # Inside an activated venv, `python` is the venv's; otherwise fall
  # back to python3. (FAQ covers the not-activated case.)
  if (nzchar(Sys.which("python"))) "python" else "python3"
}

# ── Stage: fetch ─────────────────────────────────────────────────────
stage_fetch <- function(cfg = pipeline_config(), probe = FALSE) {
  # Wraps the proven Phase 1 script unchanged. NOT in the default run:
  # a full fetch takes tens of minutes and needs the API key exported.
  # Scope (families x years) is set in the script's CONFIGURATION
  # block. probe = TRUE shows counts without downloading.
  chk <- validate_fetch_scope(cfg$fetch_families, cfg$fetch_year_from,
                              cfg$fetch_year_to, cfg$fetch_search %||% "")
  if (!chk$ok) stop("bad fetch scope: ", chk$reason)
  args <- build_fetch_args(cfg, probe = probe)
  .stage_msg("[fetch] running: %s %s", .python(), paste(args, collapse = " "))
  # stdout captured and re-emitted as messages so BOTH the Terminal
  # and the app's on-screen log see the script's output.
  out <- suppressWarnings(system2(.python(), args, stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status") %||% 0
  if (length(out) > 0) message(paste(out, collapse = "\n"))
  if (status != 0) stop("fetch failed (exit ", status,
                        ") - venv activated? OPENFDA_API_KEY exported? scope valid?")
  invisible(list(note = if (probe) "probe only" else "raw refreshed"))
}

# The R-side mirror of the fetch script's query dictionary: same
# whitelist, so the app can refuse a bad scope INSTANTLY (and the
# script re-validates anyway - defense in depth, again).
FETCH_FAMILIES <- c("hip_prosthesis", "knee_prosthesis",
                    "bone_plate", "spinal_fixation")
SEARCHABLE_FIELDS <- c("device.generic_name", "device.brand_name",
                       "device.manufacturer_d_name", "device.model_number",
                       "event_type", "product_problems", "mdr_text.text")

validate_fetch_scope <- function(families = NULL, year_from = NULL,
                                 year_to = NULL, search = "") {
  # Returns list(ok, reason) - the app shows `reason` in red.
  if (!is.null(families)) {
    bad <- setdiff(families, FETCH_FAMILIES)
    if (length(bad) > 0)
      return(list(ok = FALSE, reason = paste0("unknown family: ",
        paste(bad, collapse = ", "), " - known: ",
        paste(FETCH_FAMILIES, collapse = ", "))))
    if (length(families) == 0)
      return(list(ok = FALSE, reason = "pick at least one family"))
  }
  y0 <- year_from %||% 2020; y1 <- year_to %||% 2024
  if (!(2010 <= y0 && y0 <= y1 && y1 <= 2026))
    return(list(ok = FALSE, reason = sprintf(
      "year range %s-%s invalid (2010-2026, from <= to)", y0, y1)))
  if (nzchar(trimws(search))) {
    flds <- regmatches(search,
      gregexpr("[A-Za-z_][A-Za-z0-9_.]*(?=\\s*:)", search, perl = TRUE))[[1]]
    if (length(flds) == 0)
      return(list(ok = FALSE,
        reason = 'no field:value term found - e.g. product_problems:"Corroded"'))
    bad <- setdiff(flds, SEARCHABLE_FIELDS)
    if (length(bad) > 0)
      return(list(ok = FALSE, reason = paste0("unknown field(s): ",
        paste(bad, collapse = ", "), " - searchable: ",
        paste(SEARCHABLE_FIELDS, collapse = ", "))))
  }
  list(ok = TRUE, reason = "")
}

build_fetch_args <- function(cfg, probe = FALSE) {
  # config -> the exact CLI arguments (the tested seam between R and
  # Python; a dry-run of these args prints the resolved queries).
  args <- c("ingest/fetch_maude.py", if (probe) "--probe")
  if (!is.null(cfg$fetch_families))
    args <- c(args, "--families", paste(cfg$fetch_families, collapse = ","))
  if (!is.null(cfg$fetch_year_from))
    args <- c(args, "--year-from", cfg$fetch_year_from)
  if (!is.null(cfg$fetch_year_to))
    args <- c(args, "--year-to", cfg$fetch_year_to)
  if (nzchar(trimws(cfg$fetch_search %||% "")))
    args <- c(args, "--search", cfg$fetch_search)
  args
}

# ── Stage: probe ─────────────────────────────────────────────────────
stage_probe <- function(cfg = pipeline_config()) {
  # The look-before-you-leap stage: asks the API how many reports the
  # current fetch scope would download (a handful of cheap requests,
  # nothing saved). Pipelines never ask "continue? y/N" mid-run — an
  # unattended run can't answer — so the human decision lives BETWEEN
  # commands: run probe, read the counts, then commit to `all`.
  stage_fetch(cfg, probe = TRUE)
}

# ── Stage: load ──────────────────────────────────────────────────────
stage_load <- function(cfg = pipeline_config()) {
  # Wraps the Phase 1 loader: data/raw/*.json -> raw_events, rebuilt
  # from scratch (same raw in, same table out — reproducibility).
  status <- system2(.python(), "ingest/load_to_sqlite.py")
  if (status != 0) stop("load failed (exit ", status, ") - venv activated?")
  n <- .with_db(cfg, function(con)
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM raw_events")$n)
  .stage_msg("[load] raw_events: %s rows", format(n, big.mark = ","))
  invisible(list(rows = n))
}

# ── Stage: clean ─────────────────────────────────────────────────────
stage_clean <- function(cfg = pipeline_config()) {
  # The Phase 2 cleaning, exactly as analysis/01 does it: engine
  # transforms, then the same deliberate column selection.
  .with_db(cfg, function(con) {
    raw <- DBI::dbGetQuery(con, "SELECT * FROM raw_events") |> tibble::as_tibble()
    clean <- clean_events(raw, verbose = FALSE)
    clean_for_db <- clean |>
      dplyr::select(report_number, mdr_report_key,
                    date_received_iso, year_month,
                    event_type = event_type_clean,
                    device_family, generic_name_std,
                    brand_name, manufacturer = manufacturer_std,
                    model_number, n_devices_on_report,
                    product_problems, narrative, source_file)
    DBI::dbWriteTable(con, "clean_events", clean_for_db, overwrite = TRUE)
    .stage_msg("[clean] clean_events: %s rows (from %s raw)",
               format(nrow(clean_for_db), big.mark = ","),
               format(nrow(raw), big.mark = ","))
    invisible(list(rows = nrow(clean_for_db)))
  })
}

# ── Stage: trend ─────────────────────────────────────────────────────
stage_trend <- function(cfg = pipeline_config()) {
  .with_db(cfg, function(con) {
    events <- DBI::dbGetQuery(con,
      "SELECT report_number, device_family, year_month FROM clean_events") |>
      tibble::as_tibble()
    m <- count_monthly(events, families = cfg$families) |> add_control_limits()

    dir.create(cfg$figures_dir, showWarnings = FALSE)
    ggplot2::ggsave(file.path(cfg$figures_dir, "trend_by_family.png"),
                    plot_trends(m), width = 9, height = 10, dpi = 150)
    if (isTRUE(cfg$publish_interactive)) {
      w <- plot_trends_interactive(m)
      htmlwidgets::saveWidget(w, file.path(cfg$figures_dir, "trend_by_family.html"),
                              selfcontained = TRUE)
      file.copy(file.path(cfg$figures_dir, "trend_by_family.html"),
                file.path(cfg$interactive_dir, "trend_by_family.html"),
                overwrite = TRUE)
    }
    DBI::dbWriteTable(con, "monthly_trends",
      m |> dplyr::mutate(year_month = format(month_date, "%Y-%m")) |>
        dplyr::select(device_family, year_month, n, center, sigma,
                      ucl, lcl, status),
      overwrite = TRUE)
    .stage_msg("[trend] monthly_trends: %d rows; %d flagged",
               nrow(m), sum(m$status != "within limits"))
    invisible(list(rows = nrow(m)))
  })
}

# ── Stage: signals ───────────────────────────────────────────────────
stage_signals <- function(cfg = pipeline_config()) {
  .with_db(cfg, function(con) {
    events <- DBI::dbGetQuery(con,
      "SELECT report_number, device_family, product_problems FROM clean_events") |>
      tibble::as_tibble()
    s <- signal_stats(events, min_a = cfg$min_a,
                      min_problem_total = cfg$min_problem_total)

    ggplot2::ggsave(file.path(cfg$figures_dir, "signals_top.png"),
                    plot_top_signals(s, top_n = cfg$top_n_signals),
                    width = 9, height = 10, dpi = 150)
    if (isTRUE(cfg$publish_interactive)) {
      w <- plot_top_signals_interactive(s, top_n = cfg$top_n_signals)
      htmlwidgets::saveWidget(w, file.path(cfg$figures_dir, "signals_top.html"),
                              selfcontained = TRUE)
      file.copy(file.path(cfg$figures_dir, "signals_top.html"),
                file.path(cfg$interactive_dir, "signals_top.html"),
                overwrite = TRUE)
    }
    DBI::dbWriteTable(con, "signal_stats",
      s |> dplyr::mutate(evans_signal = as.integer(evans_signal)),
      overwrite = TRUE)
    .stage_msg("[signals] signal_stats: %d pairs; %d Evans signals",
               nrow(s), sum(s$evans_signal))
    invisible(list(rows = nrow(s)))
  })
}

# ── Stage: terms ─────────────────────────────────────────────────────
stage_terms <- function(cfg = pipeline_config()) {
  # The heavy one: tokenizing ~84K narratives takes a minute or two
  # and real RAM at full scope.
  .with_db(cfg, function(con) {
    events <- DBI::dbGetQuery(con,
      "SELECT report_number, device_family, narrative FROM clean_events") |>
      tibble::as_tibble()
    d <- tokenize_narratives(events) |>
      count_terms() |>
      distinctive_terms(min_total = cfg$min_total_terms)

    ggplot2::ggsave(file.path(cfg$figures_dir, "terms_by_family.png"),
                    plot_distinctive_terms(d),
                    width = 10, height = 7, dpi = 150)
    if (isTRUE(cfg$publish_interactive)) {
      w <- plot_term_scatter_interactive(d)
      htmlwidgets::saveWidget(w, file.path(cfg$figures_dir, "narrative_terms.html"),
                              selfcontained = TRUE)
      file.copy(file.path(cfg$figures_dir, "narrative_terms.html"),
                file.path(cfg$interactive_dir, "narrative_terms.html"),
                overwrite = TRUE)
    }
    DBI::dbWriteTable(con, "narrative_terms",
      d |> dplyr::select(device_family, word, n, per_10k, ratio, log2_ratio),
      overwrite = TRUE)
    .stage_msg("[terms] narrative_terms: %d (family, word) rows", nrow(d))
    invisible(list(rows = nrow(d)))
  })
}

# ── Stage: test — the pipeline's final gate ─────────────────────────
stage_test <- function(cfg = pipeline_config()) {
  # A pipeline that ends by verifying its own math is a pipeline you
  # can trust unattended. Non-zero exit = red run = the pipeline FAILS.
  status <- system2("Rscript", "tests/run_tests.R",
                    stdout = FALSE, stderr = FALSE)
  if (status != 0) stop("test suite FAILED - run Rscript tests/run_tests.R to see why")
  .stage_msg("[test] suite green")
  invisible(list(note = "suite green"))
}

# ── Stage: report — render + publish the executable document ────────
stage_report <- function(cfg = pipeline_config()) {
  # Renders report/orthowatch_report.qmd against the CURRENT database
  # and publishes the self-contained HTML to docs/ (the Pages copy).
  # The .qmd is source code and is never regenerated - only its
  # rendered output is. Not in the offline default (needs the quarto
  # binary; adds ~a minute); runs in `all`, or by name.
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) {
    # RStudio bundles quarto; on macOS it lives here even when the
    # plain terminal's PATH doesn't know it:
    rstudio_quarto <- "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto"
    if (file.exists(rstudio_quarto)) quarto <- rstudio_quarto
  }
  if (!nzchar(quarto) || !file.exists(quarto))
    stop("quarto binary not found - render from RStudio's Render ",
         "button instead, or install the Quarto CLI (quarto.org)")
  status <- system2(quarto, c("render", "report/orthowatch_report.qmd"))
  if (status != 0) stop("report render failed (exit ", status, ")")
  ok <- file.copy("report/orthowatch_report.html",
                  "docs/orthowatch_report.html", overwrite = TRUE)
  if (!ok) stop("could not publish report to docs/")
  .stage_msg("[report] rendered and published to docs/orthowatch_report.html")
  invisible(list(note = "report published"))
}

# The registry: name -> function, in canonical order. The runner (and
# later the app) iterate over this — adding a stage = one entry here.
PIPELINE_STAGES <- list(
  probe   = stage_probe,
  fetch   = stage_fetch,
  load    = stage_load,
  clean   = stage_clean,
  trend   = stage_trend,
  signals = stage_signals,
  terms   = stage_terms,
  test    = stage_test,
  report  = stage_report
)

# The default run is OFFLINE: everything downstream of the raw files.
# fetch is opt-in (long, needs the API key): by name, or via `all`,
# which runs fetch -> load -> ... -> test (probe stays separate — it's
# the human's decision step, run on its own BEFORE committing to all).
DEFAULT_STAGES <- c("load", "clean", "trend", "signals", "terms", "test")
