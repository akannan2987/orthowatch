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
source("../R/trending.R")
source("../R/signal_detection.R")
source("../R/text_mining.R")

DB_PATH <- "../data/processed/orthowatch.db"

# ── Global section: runs ONCE when the app starts ────────────────────
con <- dbConnect(RSQLite::SQLite(), DB_PATH)
onStop(function() dbDisconnect(con))   # tidy up when the app stops

monthly <- dbGetQuery(con, "SELECT * FROM monthly_trends") |>
  as_tibble() |>
  mutate(month_date = as.Date(paste0(year_month, "-01")))

signals <- dbGetQuery(con, "SELECT * FROM signal_stats") |>
  as_tibble() |>
  mutate(evans_signal = as.logical(evans_signal))  # SQLite stores 0/1

# narrative_terms stores rates but not the other-families denominators
# the scatter needs — recover them from what IS stored:
#   per_10k = 1e4 * n / family_total   =>   family_total = 1e4*n/per_10k
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

FAMILIES <- sort(unique(monthly$device_family))
n_reports <- dbGetQuery(con,
  "SELECT COUNT(*) AS n FROM clean_events")$n

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

  # ---- Trends tab ----------------------------------------------------
  output$trend_plot <- renderPlotly({
    req(input$trend_families)              # wait until >= 1 family ticked
    monthly |>
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
    plot_top_signals_interactive(signals, top_n = input$sig_top_n,
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
    plot_term_scatter_interactive(terms,
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
}

shinyApp(ui, server)
