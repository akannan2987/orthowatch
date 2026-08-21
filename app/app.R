# app.R — OrthoWatch dashboard (Phase 6)
# =========================================================
# One file, two halves, same as every Shiny app:
#   ui     — WHAT the user sees (tabs, dropdowns, chart areas)
#   server — WHAT HAPPENS when they interact (filter, redraw, query)
# shinyApp(ui, server) at the bottom starts a live R process that
# serves the page and re-runs the relevant server code on every click
# — the "spreadsheet recalculation" model: outputs that depend on an
# input recompute automatically when that input changes.
#
# Run it (from the project root):    shiny::runApp("app")
# Stop it:                           the red STOP button / Ctrl+C
#
# Design notes, so nothing is magic:
# * The three charts are the SAME tested functions the analysis
#   scripts use (R/trending.R etc.) — the dashboard adds no new
#   statistics, only assembly. One engine, many consumers.
# * Small result tables (trends, signals, terms) are loaded ONCE at
#   startup from the database. The big table (clean_events, with 84K
#   narratives) is NOT loaded: drill-downs query it live, per click,
#   with parameterized SQL — the database does the heavy lifting and
#   the app stays light.
# * Every drill-down is guarded with req(): "do nothing until the
#   user has actually clicked something."

library(shiny)
library(DT)          # interactive tables (sort/search/page in the browser)
library(DBI)
library(RSQLite)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(plotly)

# Shiny runs an app with the APP'S OWN FOLDER as the working
# directory (true for runApp("app"), for RStudio's Run App button,
# and for headless tests alike) — so everything in the project root
# is one level UP from here:
source("../R/clean_events.R")
source("../R/trending.R")
source("../R/signal_detection.R")
source("../R/text_mining.R")
source("../R/console.R")
source("../R/run_history.R")
source("../pipeline/config.R")
source("../pipeline/stages.R")

DB_PATH <- "../data/processed/orthowatch.db"
# Absolute from the start: handlers that temporarily change directory
# (pipeline, ingest, report) can then reach the database - and the
# ledger - from anywhere. Relative paths are for humans; long-lived
# handles want absolutes.
DB_PATH <- normalizePath(DB_PATH, mustWork = FALSE)

# ── Global section: runs ONCE when the app starts ────────────────────
con <- dbConnect(RSQLite::SQLite(), DB_PATH)
onStop(function() dbDisconnect(con))   # tidy up when the app stops

# All small result tables load through ONE function — because Phase
# 8's Pipeline tab can CHANGE those tables, and after a run the app
# must be able to reload them without restarting. State that can be
# refreshed lives in a function; the server keeps it in a reactiveVal.
load_small_tables <- function(con) {
  monthly <- dbGetQuery(con, "SELECT * FROM monthly_trends") |>
    as_tibble() |>
    mutate(month_date = as.Date(paste0(year_month, "-01")))

  signals <- dbGetQuery(con, "SELECT * FROM signal_stats") |>
    as_tibble() |>
    mutate(evans_signal = as.logical(evans_signal))  # SQLite stores 0/1

  # narrative_terms stores rates but not the other-families
  # denominators the scatter needs — recover them from what IS stored:
  #   per_10k = 1e4 * n / family_total  =>  family_total = 1e4*n/per_10k
  terms <- dbGetQuery(con, "SELECT * FROM narrative_terms") |> as_tibble()
  fam_tot <- terms |>
    mutate(family_total = round(1e4 * n / per_10k)) |>
    group_by(device_family) |>
    summarise(family_total = max(family_total), .groups = "drop")
  grand_total <- sum(fam_tot$family_total)
  terms <- terms |>
    left_join(fam_tot, by = "device_family") |>
    group_by(word) |>
    mutate(word_total = sum(n)) |>
    ungroup() |>
    mutate(n_others = word_total - n,
           others_total = grand_total - family_total)

  list(monthly = monthly, signals = signals, terms = terms,
       n_reports = dbGetQuery(con,
         "SELECT COUNT(*) AS n FROM clean_events")$n)
}

.d0 <- load_small_tables(con)          # first load, at startup
FAMILIES <- sort(unique(.d0$monthly$device_family))
n_reports <- .d0$n_reports

# The stages the Pipeline tab offers. fetch is deliberately absent:
# a 30-minute credentialed download does not belong behind a button
# that freezes the browser — it stays Terminal territory (the tab
# says so). probe is offered (it's the free look) with a time note.
MC_STAGES <- c("probe", "load", "clean", "trend", "signals",
               "terms", "test", "report")

# The query dictionary, as shown to the user (mirrors the whitelist in
# ingest/fetch_maude.py - the script re-validates everything anyway).
QUERY_DICT <- data.frame(
  field = c("device.generic_name", "device.brand_name",
            "device.manufacturer_d_name", "device.model_number",
            "event_type", "product_problems", "mdr_text.text"),
  meaning = c("device type as FDA names it", "product/brand name",
              "manufacturer name", "model number",
              "Injury / Malfunction / Death / Other",
              "coded problem term", "words in the narrative text"),
  example = c('device.generic_name:(shoulder AND prosthesis)',
              'device.brand_name:ATTUNE',
              'device.manufacturer_d_name:ZIMMER',
              'device.model_number:12345',
              'event_type:Malfunction',
              'product_problems:"Corroded"',
              'mdr_text.text:(cobalt AND revision)'))

DATA_TABLES <- c("monthly_trends", "signal_stats", "narrative_terms",
                 "clean_events", "raw_events")

trunc_col <- function(x, n = 60) str_trunc(coalesce(x, ""), n)

# ── UI: what the user sees ───────────────────────────────────────────
ui <- navbarPage(
  title = "OrthoWatch",

  tabPanel("Overview",
    fluidRow(column(8, offset = 2,
      h3("Post-market surveillance of orthopedic device reports"),
      p(sprintf("%s cleaned FDA MAUDE reports (2020–2024) across %d
        device families, screened for temporal anomalies (control
        charts), device–problem associations (PRR/ROR), and narrative
        patterns (text mining).",
        format(n_reports, big.mark = ","), length(FAMILIES))),
      uiOutput("provenance"),
      tags$ul(
        tags$li(strong("Trends"), " — monthly reports with 3-sigma
          control limits; click any point for that month's reports."),
        tags$li(strong("Signals"), " — each family's strongest
          disproportionality signals; click a dot for the reports
          behind it."),
        tags$li(strong("Narratives"), " — each family's distinctive
          vocabulary; click a word-dot to read sampled narratives.")
      ),
      hr(),
      p(em("Honesty note: these are unverified reporter submissions.
        Report counts reflect reporting behavior as much as device
        performance; flags and signals mean investigate, never
        unsafe. Nothing here is a finding about any product.")))
    )
  ),

  tabPanel("Trends",
    sidebarLayout(
      sidebarPanel(width = 3,
        checkboxGroupInput("trend_families", "Device families",
                           choices = FAMILIES, selected = FAMILIES),
        helpText("Grey band = expected range if reporting were steady
                 (mean ± 3 sd). Click any point to see that month's
                 reports below.")
      ),
      mainPanel(width = 9,
        plotlyOutput("trend_plot", height = "520px"),
        hr(),
        h4(textOutput("trend_click_title")),
        DTOutput("trend_drill")
      )
    )
  ),

  tabPanel("Signals",
    sidebarLayout(
      sidebarPanel(width = 3,
        sliderInput("sig_top_n", "Signals per family", min = 3,
                    max = 10, value = 5, step = 1),
        helpText("Dot = reporting odds ratio; whiskers = 95% CI;
                 dashed line = reported no more than everyone else.
                 All shown pass the Evans rule. Click a dot to see
                 the reports behind it.")
      ),
      mainPanel(width = 9,
        plotlyOutput("signal_plot", height = "700px"),
        hr(),
        h4(textOutput("signal_click_title")),
        DTOutput("signal_drill")
      )
    )
  ),

  tabPanel("Narratives",
    sidebarLayout(
      sidebarPanel(width = 3,
        sliderInput("term_min_rate", "Min. rate (per 10k words)",
                    min = 0, max = 10, value = 1, step = 0.5),
        helpText("Every dot is a word; below the diagonal = that
                 family's own vocabulary. Click a dot to read three
                 sampled narratives containing the word.")
      ),
      mainPanel(width = 9,
        plotlyOutput("term_plot", height = "560px"),
        hr(),
        h4(textOutput("term_click_title")),
        uiOutput("term_drill")
      )
    )
  ),

  tabPanel("Ingest",
    sidebarLayout(
      sidebarPanel(width = 4,
        checkboxGroupInput("ing_families", "Device families",
          choices = c("hip_prosthesis", "knee_prosthesis",
                      "bone_plate", "spinal_fixation"),
          selected = "bone_plate"),
        fluidRow(
          column(6, numericInput("ing_y0", "From year", 2024,
                                 min = 2010, max = 2026, step = 1)),
          column(6, numericInput("ing_y1", "To year", 2024,
                                 min = 2010, max = 2026, step = 1))),
        textInput("ing_search", "Extra search term (optional)",
          value = "", placeholder = 'e.g. product_problems:"Corroded"'),
        helpText("Fields must come from the query dictionary (right).
                 Everything is validated BEFORE any network call —
                 a typo fails instantly, with a reason, not after a
                 silent zero-match download."),
        actionButton("ing_probe", "Probe this scope",
                     class = "btn-primary"),
        actionButton("ing_fetch", "Fetch this scope"),
        helpText("Probe = free look (counts only, ~seconds per slice).
                 Fetch downloads into data/raw/ and BLOCKS the browser
                 ~1–3 min per family-year — keep scopes small here;
                 the full refresh stays in the Terminal
                 (`Rscript run_pipeline.R all`). After a fetch, run
                 load → clean → analyses on the Pipeline tab."),
        uiOutput("ing_status")
      ),
      mainPanel(width = 8,
        h4("Query dictionary — searchable openFDA fields"),
        tableOutput("ing_dict"),
        h4("Log"),
        verbatimTextOutput("ing_log", placeholder = TRUE)
      )
    )
  ),

  tabPanel("Pipeline",
    sidebarLayout(
      sidebarPanel(width = 3,
        checkboxGroupInput("mc_stages", "Stages to run",
                           choices = MC_STAGES,
                           selected = c("trend", "signals", "test")),
        actionButton("mc_run", "Run selected stages",
                     class = "btn-primary"),
        helpText("Stages run in canonical order regardless of tick
                 order. The browser WAITS while R works (one session,
                 one lane): terms ~45s, probe ~1 min, report ~20s.
                 The full fetch is deliberately not offered here —
                 30+ minutes and an API key belong in the Terminal
                 (`Rscript run_pipeline.R all`)."),
        hr(),
        actionButton("mc_reload", "Reload results into dashboard"),
        helpText("Runs from this tab refresh the dashboard
                 automatically. Use this button when the database
                 changed OUTSIDE the app (a Terminal pipeline run).")
      ),
      mainPanel(width = 9,
        h4("Run log"),
        verbatimTextOutput("mc_log", placeholder = TRUE),
        h4("Timings"),
        tableOutput("mc_timings"),
        hr(),
        h4("Run history"),
        p(class = "text-muted", "The ledger: every probe, fetch,
          pipeline run, and report render — including failures.
          Stored in the database (table run_history), so it survives
          restarts and is queryable from the Query tab."),
        DTOutput("mc_history")
      )
    )
  ),

  tabPanel("Query",
    sidebarLayout(
      sidebarPanel(width = 3,
        helpText("Read-only by construction: only a single SELECT (or
                 WITH) runs, on a connection that cannot write —
                 two independent locks. Results cap at 200 rows."),
        h5("Tables"),
        verbatimTextOutput("q_schema", placeholder = TRUE)
      ),
      mainPanel(width = 9,
        textAreaInput("q_sql", label = NULL, rows = 5, width = "100%",
          value = paste("SELECT device_family, COUNT(*) AS reports",
                        "FROM clean_events",
                        "GROUP BY device_family ORDER BY reports DESC")),
        actionButton("q_run", "Run query", class = "btn-primary"),
        br(), br(),
        uiOutput("q_status"),
        DTOutput("q_result")
      )
    )
  ),

  tabPanel("Data",
    sidebarLayout(
      sidebarPanel(width = 3,
        selectInput("dt_table", "Table", choices = DATA_TABLES),
        helpText("Sort by clicking a column header; filter with the
                 boxes under the headers. The two big event tables
                 display without the narrative column (it's huge) —
                 downloads always contain EVERY column and row."),
        hr(),
        h5("Download this table"),
        downloadButton("dl_csv",  "CSV"),
        downloadButton("dl_xlsx", "Excel"),
        downloadButton("dl_json", "JSON"),
        helpText("clean_events / raw_events are large (tens of MB) —
                 the download takes a moment to prepare."),
        hr(),
        h5("Download a figure"),
        selectInput("dl_fig_pick", NULL,
                    choices = basename(Sys.glob("../figures/*.png"))),
        downloadButton("dl_fig", "PNG"),
        helpText("Interactive charts also have a camera icon (top
                 right on hover) that saves exactly what you see."),
        hr(),
        h5("Download the report"),
        downloadButton("dl_report", "Report (HTML)")
      ),
      mainPanel(width = 9,
        h4(textOutput("dt_title")),
        DTOutput("dt_browse")
      )
    )
  ),

  tabPanel("Report",
    fluidRow(column(8, offset = 2,
      h3("The executable report"),
      p("Renders report/orthowatch_report.qmd against the CURRENT
        database — every number recomputed — and publishes the
        self-contained HTML to docs/. Takes ~20 seconds; the browser
        waits while it works."),
      actionButton("rp_render", "Render & publish report",
                   class = "btn-primary"),
      br(), br(),
      uiOutput("rp_status")
    ))
  ),

  tabPanel("About",
    fluidRow(column(8, offset = 2,
      h4("How this app is built"),
      p("The charts are the same tested functions the analysis
        scripts use (R/ directory; 42 automated tests). Small result
        tables load once at startup; every drill-down queries the
        SQLite database live with parameterized SQL. Source, docs,
        and the full build story:"),
      a("github.com/akannan2987/orthowatch",
        href = "https://github.com/akannan2987/orthowatch"),
      hr(),
      p("Data: FDA MAUDE via openFDA (device adverse event reports,
        2020–2024). MAUDE data is unverified, incomplete, and cannot
        be used to compare devices or estimate incidence rates.")
    ))
  )
)

# ── Server: what happens when the user interacts ─────────────────────
server <- function(input, output, session) {

  # The ledger, as refreshable state - reread after every recorded run.
  RUNS <- reactiveVal(read_run_history(DB_PATH))

  output$provenance <- renderUI({
    h <- RUNS()
    piped <- h[h$kind %in% c("pipeline", "fetch") & h$outcome == "ok", ]
    if (nrow(piped) == 0)
      return(tags$p(class = "text-muted", em("No recorded runs yet —
        results below are from the database as found at startup.")))
    r <- piped[1, ]
    tags$p(class = "text-muted", em(sprintf(
      "Results from: %s (%s) — %s, %s.",
      r$kind, r$detail, r$outcome, r$run_at)))
  })

  output$mc_history <- renderDT({
    h <- RUNS()
    datatable(h, rownames = FALSE, filter = "top",
              options = list(pageLength = 5, dom = "tp", scrollX = TRUE))
  })

  # The dashboard's data, as refreshable state: DATA() reads it,
  # DATA(load_small_tables(con)) replaces it and every output that
  # read it recomputes — the same spreadsheet model, applied to the
  # app's own tables.
  DATA <- reactiveVal(.d0)

  # ---- Trends tab ----------------------------------------------------
  output$trend_plot <- renderPlotly({
    req(input$trend_families)              # wait until >= 1 family ticked
    DATA()$monthly |>
      filter(device_family %in% input$trend_families) |>
      plot_trends_interactive(source = "trends")
  })

  # event_data() is plotly's bridge into Shiny: it returns a small
  # data frame describing the last click on the chart named by
  # `source` — including the customdata ("family|YYYY-MM") the engine
  # attached to every point.
  trend_click <- reactive({
    d <- event_data("plotly_click", source = "trends")
    req(d$customdata)                      # NULL until the first click
    strsplit(d$customdata, "|", fixed = TRUE)[[1]]   # c(family, month)
  })

  output$trend_click_title <- renderText({
    ck <- trend_click()
    sprintf("Reports for %s, %s", ck[1], ck[2])
  })

  output$trend_drill <- renderDT({
    ck <- trend_click()
    # Parameterized query (the ?s): values travel separately from the
    # SQL text, so a weird string can never rewrite the query — the
    # standard defense against SQL injection, and good hygiene even
    # in a local app.
    rows <- dbGetQuery(con, "
      SELECT report_number, event_type, manufacturer, product_problems
      FROM clean_events
      WHERE device_family = ? AND year_month = ?
      LIMIT 15", params = list(ck[1], ck[2])) |>
      mutate(product_problems = trunc_col(product_problems))
    datatable(rows, options = list(pageLength = 5, dom = "tp"),
              rownames = FALSE,
              caption = "First 15 reports of that month (of all in the database).")
  })

  # ---- Signals tab ---------------------------------------------------
  output$signal_plot <- renderPlotly({
    plot_top_signals_interactive(DATA()$signals, top_n = input$sig_top_n,
                                 source = "signals")
  })

  signal_click <- reactive({
    d <- event_data("plotly_click", source = "signals")
    req(d$customdata)
    strsplit(d$customdata, "|", fixed = TRUE)[[1]]   # c(family, problem)
  })

  output$signal_click_title <- renderText({
    ck <- signal_click()
    sprintf("%s reports mentioning \u201C%s\u201D", ck[1], ck[2])
  })

  output$signal_drill <- renderDT({
    ck <- signal_click()
    rows <- dbGetQuery(con, "
      SELECT report_number, event_type, manufacturer, product_problems
      FROM clean_events
      WHERE device_family = ? AND product_problems LIKE ?
      LIMIT 15", params = list(ck[1], paste0("%", ck[2], "%"))) |>
      mutate(product_problems = trunc_col(product_problems, 80))
    datatable(rows, options = list(pageLength = 5, dom = "tp"),
              rownames = FALSE,
              caption = "First 15 matching reports; the signal's `a` counts them all.")
  })

  # ---- Narratives tab ------------------------------------------------
  output$term_plot <- renderPlotly({
    plot_term_scatter_interactive(DATA()$terms,
                                  min_per_10k = input$term_min_rate,
                                  source = "terms")
  })

  term_click <- reactive({
    d <- event_data("plotly_click", source = "terms")
    req(d$customdata)
    strsplit(d$customdata, "|", fixed = TRUE)[[1]]   # c(family, word)
  })

  output$term_click_title <- renderText({
    ck <- term_click()
    sprintf("Sampled %s narratives containing \u201C%s\u201D", ck[1], ck[2])
  })

  output$term_drill <- renderUI({
    ck <- term_click()
    # SQLite's LIKE is case-insensitive for plain letters, so the
    # lowercase token matches the uppercase narratives.
    rows <- dbGetQuery(con, "
      SELECT narrative FROM clean_events
      WHERE device_family = ? AND narrative LIKE ?
      LIMIT 3", params = list(ck[1], paste0("%", ck[2], "%")))
    req(nrow(rows) > 0)
    tagList(lapply(rows$narrative, function(x)
      tags$blockquote(style = "font-size: 90%;", str_trunc(x, 600))))
  })

  # ---- Pipeline tab (Mission Control) -------------------------------
  mc_log     <- reactiveVal("(no run yet)")
  mc_timings <- reactiveVal(NULL)

  observeEvent(input$mc_run, {
    req(input$mc_stages)
    # Canonical order, exactly like the runner: the UI wraps the
    # pipeline, so it inherits the pipeline's rules for free.
    stages <- names(PIPELINE_STAGES)[names(PIPELINE_STAGES) %in%
                                       input$mc_stages]
    cfg <- pipeline_config()
    # The app lives in app/; the stages assume the project root.
    owd <- getwd(); on.exit(setwd(owd), add = TRUE); setwd("..")

    lines <- character(); times <- data.frame()
    withProgress(message = "Pipeline running", value = 0, {
      for (i in seq_along(stages)) {
        s <- stages[i]
        incProgress(1 / length(stages), detail = s)
        t0 <- Sys.time()
        # Capture each stage's message() lines into the on-screen log.
        ok <- tryCatch({
          withCallingHandlers(
            PIPELINE_STAGES[[s]](cfg),
            message = function(m) {
              lines <<- c(lines, sub("\n$", "", conditionMessage(m)))
              invokeRestart("muffleMessage")
            })
          TRUE
        }, error = function(e) {
          lines <<- c(lines, paste0("ERROR in ", s, ": ",
                                    conditionMessage(e)))
          FALSE
        })
        times <- rbind(times, data.frame(
          stage = s,
          seconds = round(as.numeric(difftime(Sys.time(), t0,
                                              units = "secs")), 1)))
        if (!ok) break                      # stop-on-error, like the runner
      }
    })
    mc_log(paste(lines, collapse = "\n"))
    mc_timings(times)

    # The ledger line for this run - failures included, honestly.
    record_run(DB_PATH, "pipeline", paste(stages, collapse = ", "),
               if (ok) "ok" else "error",
               summary = paste(lines[grepl("^\\[", lines)], collapse = " | "),
               seconds = sum(times$seconds))
    RUNS(read_run_history(DB_PATH))

    # AUTO-refresh: a run that changed the tables refreshes the
    # dashboard by itself (the Reload button remains for db changes
    # made OUTSIDE the app, e.g. a Terminal pipeline run).
    if (ok) {
      DATA(load_small_tables(con))
      showNotification("Run recorded; dashboard refreshed.", type = "message")
    }
  })

  observeEvent(input$mc_reload, {
    DATA(load_small_tables(con))            # the refresh: state swaps,
    showNotification("Dashboard tables reloaded.", type = "message")
  })                                        # dependents recompute

  output$mc_log     <- renderText(mc_log())
  output$mc_timings <- renderTable(mc_timings())

  # ---- Query tab (read-only console) --------------------------------
  output$q_schema <- renderText({
    tabs <- dbListTables(con)
    paste(vapply(tabs, function(tb) {
      cols <- dbGetQuery(con, paste0("PRAGMA table_info(", tb, ")"))$name
      paste0(tb, "\n  ", paste(cols, collapse = ", "))
    }, character(1)), collapse = "\n\n")
  })

  q_out <- eventReactive(input$q_run, {
    # Both locks live in R/console.R - tested, not hoped.
    tryCatch(
      list(ok = TRUE,
           data = run_readonly_query(DB_PATH, input$q_sql,
                                     max_rows = 200)),
      error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
  })

  output$q_status <- renderUI({
    r <- q_out()
    if (!r$ok)
      return(tags$p(style = "color: #b30000;",
                    strong("Refused: "), r$msg))
    trunc <- isTRUE(attr(r$data, "truncated"))
    tags$p(sprintf("%d row(s)%s.", nrow(r$data),
                   if (trunc) " (capped at 200)" else ""))
  })

  output$q_result <- renderDT({
    r <- q_out(); req(r$ok)
    datatable(r$data, options = list(pageLength = 10, dom = "tp",
                                     scrollX = TRUE), rownames = FALSE)
  })

  # ---- Ingest tab ----------------------------------------------------
  output$ing_dict <- renderTable(QUERY_DICT, striped = TRUE)
  ing_log <- reactiveVal("(no probe or fetch yet)")
  ing_msg <- reactiveVal(NULL)

  ing_scope_cfg <- function() {
    cfg <- pipeline_config()
    cfg$fetch_families  <- input$ing_families
    cfg$fetch_year_from <- input$ing_y0
    cfg$fetch_year_to   <- input$ing_y1
    cfg$fetch_search    <- input$ing_search
    cfg
  }

  run_scoped <- function(probe) {
    chk <- validate_fetch_scope(input$ing_families, input$ing_y0,
                                input$ing_y1, input$ing_search)
    if (!chk$ok) { ing_msg(chk$reason); return(invisible()) }
    ing_msg(NULL)
    owd <- getwd(); on.exit(setwd(owd), add = TRUE); setwd("..")
    lines <- character()
    withProgress(message = if (probe) "Probing scope" else "Fetching scope",
                 value = 0.4, {
      tryCatch(
        withCallingHandlers(
          stage_fetch(ing_scope_cfg(), probe = probe),
          message = function(m) {
            lines <<- c(lines, sub("\\n$", "", conditionMessage(m)))
            invokeRestart("muffleMessage")
          }),
        error = function(e) lines <<- c(lines, paste0("ERROR: ",
                                                      conditionMessage(e))))
    })
    ing_log(paste(lines, collapse = "\n"))

    scope <- sprintf("%s | %s-%s%s",
                     paste(input$ing_families, collapse = ","),
                     input$ing_y0, input$ing_y1,
                     if (nzchar(trimws(input$ing_search)))
                       paste0(" | ", input$ing_search) else "")
    failed <- any(grepl("^ERROR", lines))
    record_run(DB_PATH, if (probe) "probe" else "fetch", scope,
               if (failed) "error" else "ok",
               summary = paste(utils::tail(lines, 3), collapse = " | "))
    RUNS(read_run_history(DB_PATH))
  }
  observeEvent(input$ing_probe, run_scoped(probe = TRUE))
  observeEvent(input$ing_fetch, run_scoped(probe = FALSE))

  output$ing_status <- renderUI({
    req(ing_msg())
    tags$p(style = "color: #b30000;", strong("Invalid scope: "), ing_msg())
  })
  output$ing_log <- renderText(ing_log())

  # ---- Data tab ------------------------------------------------------
  dt_data <- reactive({
    input$mc_reload                       # refresh after pipeline runs
    tbl <- input$dt_table
    # The big event tables come to the BROWSER without narrative (it is
    # enormous); downloads (below) always query the full table fresh.
    if (tbl %in% c("clean_events", "raw_events")) {
      cols <- setdiff(dbGetQuery(con,
        paste0("PRAGMA table_info(", tbl, ")"))$name,
        c("narrative", "mdr_text"))
      dbGetQuery(con, paste0("SELECT ", paste(cols, collapse = ", "),
                             " FROM ", tbl))
    } else {
      dbGetQuery(con, paste0("SELECT * FROM ", tbl))
    }
  })
  output$dt_title <- renderText(sprintf("%s — %s rows", input$dt_table,
    format(nrow(dt_data()), big.mark = ",")))
  output$dt_browse <- renderDT(
    datatable(dt_data(), filter = "top", rownames = FALSE,
              options = list(pageLength = 10, scrollX = TRUE)))

  dl_frame <- function() dbGetQuery(con,
    paste0("SELECT * FROM ", input$dt_table))   # full table, every column
  output$dl_csv <- downloadHandler(
    filename = function() paste0(input$dt_table, ".csv"),
    contentType = "text/csv",
    content = function(file) write.csv(dl_frame(), file, row.names = FALSE))
  output$dl_xlsx <- downloadHandler(
    filename = function() paste0(input$dt_table, ".xlsx"),
    contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    content = function(file) writexl::write_xlsx(dl_frame(), file))
  output$dl_json <- downloadHandler(
    filename = function() paste0(input$dt_table, ".json"),
    contentType = "application/json",
    content = function(file) jsonlite::write_json(dl_frame(), file,
                                                  dataframe = "rows"))
  output$dl_fig <- downloadHandler(
    filename = function() input$dl_fig_pick,
    content = function(file) file.copy(
      file.path("../figures", input$dl_fig_pick), file))
  output$dl_report <- downloadHandler(
    filename = function() "orthowatch_report.html",
    content = function(file) {
      req(file.exists("../docs/orthowatch_report.html"))
      file.copy("../docs/orthowatch_report.html", file)
    })

  # ---- Report tab ----------------------------------------------------
  rp_msg <- reactiveVal(NULL)
  observeEvent(input$rp_render, {
    owd <- getwd(); on.exit(setwd(owd), add = TRUE); setwd("..")
    withProgress(message = "Rendering report", value = 0.4, {
      res <- tryCatch({ stage_report(pipeline_config()); TRUE },
                      error = function(e) conditionMessage(e))
    })
    rp_msg(res)
    record_run(DB_PATH, "report", "render + publish",
               if (isTRUE(res)) "ok" else "error",
               summary = if (isTRUE(res)) "docs/orthowatch_report.html"
                         else as.character(res))
    RUNS(read_run_history(DB_PATH))
  })
  output$rp_status <- renderUI({
    r <- rp_msg(); req(!is.null(r))
    if (isTRUE(r))
      tagList(
        tags$p(style = "color: #1a7a1a;", strong("Rendered & published. "),
               "Fresh copy at docs/orthowatch_report.html — live at the
                project's Pages URL after the next commit+push."),
        tags$a(href = "https://akannan2987.github.io/orthowatch/orthowatch_report.html",
               target = "_blank", "Open the live report (last published version)"))
    else
      tags$p(style = "color: #b30000;", strong("Render failed: "), r)
  })
}

shinyApp(ui, server)
