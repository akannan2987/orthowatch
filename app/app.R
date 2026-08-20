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
source("../pipeline/config.R")
source("../pipeline/stages.R")

DB_PATH <- "../data/processed/orthowatch.db"

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
        helpText("After a run changes the tables, this refreshes the
                 Trends/Signals/Narratives tabs without restarting.")
      ),
      mainPanel(width = 9,
        h4("Run log"),
        verbatimTextOutput("mc_log", placeholder = TRUE),
        h4("Timings"),
        tableOutput("mc_timings")
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
    owd <- setwd(".."); on.exit(setwd(owd), add = TRUE)

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

  # ---- Report tab ----------------------------------------------------
  rp_msg <- reactiveVal(NULL)
  observeEvent(input$rp_render, {
    owd <- setwd(".."); on.exit(setwd(owd), add = TRUE)
    withProgress(message = "Rendering report", value = 0.4, {
      res <- tryCatch({ stage_report(pipeline_config()); TRUE },
                      error = function(e) conditionMessage(e))
    })
    rp_msg(res)
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
