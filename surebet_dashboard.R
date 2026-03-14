# surebet_dashboard.R — SureBet Archer Dashboard
# Run with: shiny::runApp("surebet_dashboard.R")
# Reads from logs/ directory relative to working directory.
# Set wd to SureBet root before launching: setwd("C:/Users/jacks/OneDrive/Documents/SureBet")

library(shiny)
library(DT)
library(dplyr)
library(readr)
library(purrr)

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- navbarPage("SureBet Archer Dashboard",

  tabPanel("Paper Log",
    DTOutput("log_table")
  ),

  tabPanel("Latest Picks",
    DTOutput("picks_table")
  ),

  tabPanel("ROI Trend",
    plotOutput("roi_plot", height = "400px")
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output) {

  # ── Reactive: load all paper trading log CSVs ──────────────────────────────
  logs <- reactive({
    csv_files <- Sys.glob("logs/paper*log*.csv")
    if (length(csv_files) == 0) {
      return(tibble(date = Sys.Date(), msg = "Fresh start — run pipeline first!"))
    }
    map_dfr(csv_files, ~ read_csv(.x, col_types = cols(
      date              = col_date(),
      starting_bankroll = col_double(),
      ending_bankroll   = col_double(),
      daily_roi         = col_double(),
      cumulative_roi    = col_double(),
      wins              = col_integer(),
      losses            = col_integer(),
      .default          = col_guess()
    ), show_col_types = FALSE))
  })

  # ── Tab 1: Paper Log ───────────────────────────────────────────────────────
  output$log_table <- renderDT({
    df <- logs()
    # Round numeric columns only — preserves character columns (sport names etc.)
    df <- df %>%
      mutate(across(where(is.double), ~ round(.x, 3)))
    datatable(df,
              extensions = "Buttons",
              options    = list(
                dom        = "Bfrtip",
                pageLength = 20,
                buttons    = c("copy", "csv", "excel")
              ))
  })

  # ── Tab 2: Latest Picks ────────────────────────────────────────────────────
  output$picks_table <- renderDT({
    picks_files <- Sys.glob("logs/daily_picks_*.csv")
    if (length(picks_files) == 0) {
      return(datatable(tibble(msg = "Run cap_daily_bets() first!")))
    }
    # Always load the most recent daily picks file
    latest <- tail(sort(picks_files), 1)
    df <- read_csv(latest, col_types = cols(
      Date     = col_character(),
      Odds     = col_double(),
      EV       = col_double(),
      Kelly    = col_double(),
      `Risk $` = col_double(),
      .default = col_character()
    ), show_col_types = FALSE) %>%
      select(any_of(c("Sport", "Date", "Time (ET)", "Home", "Away",
                      "Bet Type", "Pick", "Odds", "Book",
                      "EV", "Kelly", "Risk $")))

    dt <- datatable(df,
              extensions = "Buttons",
              options    = list(
                dom        = "Bfrtip",
                pageLength = 25,
                buttons    = c("copy", "csv", "excel")
              ))

    # Format numeric columns for consistent display
    if ("Odds"   %in% names(df)) dt <- formatRound(dt,   "Odds",   digits = 2)
    if ("EV"     %in% names(df)) dt <- formatRound(dt,   "EV",     digits = 1)
    if ("Kelly"  %in% names(df)) dt <- formatRound(dt,   "Kelly",  digits = 4)
    if ("Risk $" %in% names(df)) dt <- formatCurrency(dt, "Risk $", currency = "$",
                                                       digits = 2, before = TRUE)
    dt
  })

  # ── Tab 3: ROI Trend ───────────────────────────────────────────────────────
  output$roi_plot <- renderPlot({
    logs_df <- logs()
    # Need at least date + daily_roi columns to plot
    if (!all(c("date", "daily_roi") %in% names(logs_df)) || nrow(logs_df) < 2) {
      plot(1, 1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "More days needed to plot ROI trend", cex = 1.2)
      return()
    }
    plot_df <- logs_df %>%
      arrange(date) %>%
      mutate(daily_roi_pct = as.numeric(daily_roi) * 100)

    plot(plot_df$date, plot_df$daily_roi_pct,
         type = "b", pch = 19, col = "#2E86AB",
         ylab = "Daily ROI %", xlab = "Date",
         main = "Bankroll Evolution — Daily ROI",
         las  = 1)
    abline(h = 0, lty = 2, col = "gray50")
    # Shade positive/negative regions
    positive <- plot_df$daily_roi_pct >= 0
    points(plot_df$date[positive],  plot_df$daily_roi_pct[positive],
           pch = 19, col = "#27AE60")
    points(plot_df$date[!positive], plot_df$daily_roi_pct[!positive],
           pch = 19, col = "#E74C3C")
  })
}

shinyApp(ui, server)
