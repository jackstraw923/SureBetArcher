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

  tabPanel("Settled Bets",
    fluidRow(
      column(12,
        h4("All Settled Bets — W/L across all sports and dates"),
        p("Loads all bet_log, spread_total_log, soccer, tennis, and challenger CSVs with a W or L result.",
          style = "color: #666; font-size: 0.9em;")
      )
    ),
    DTOutput("settled_table")
  ),

  tabPanel("Arb Alerts",
    fluidRow(
      column(12,
        h4("Arbitrage Opportunities in Today's Picks"),
        p("Games where SureBet picked BOTH sides on ML — guaranteed profit if staked correctly.",
          style = "color: #666; font-size: 0.9em;"),
        p("Arb profit % = (1 - (1/odds_side1 + 1/odds_side2)) x 100. True arb = sum of implied probs < 1.",
          style = "color: #888; font-size: 0.85em; font-style: italic;")
      )
    ),
    DTOutput("arb_table")
  ),

  tabPanel("ROI Trend",
    plotOutput("roi_plot", height = "400px")
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output) {

  # ── Reactive: paper trading log ───────────────────────────────────────────
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

  # ── Reactive: all settled bets across all log files ───────────────────────
  settled_bets <- reactive({
    all_files <- c(
      Sys.glob("logs/bet_log_*.csv"),
      Sys.glob("logs/spread_total_log_*.csv"),
      Sys.glob("logs/soccer_bet_log_*.csv"),
      Sys.glob("logs/tennis_bet_log_*.csv"),
      Sys.glob("logs/challenger_bet_log_*.csv")
    )
    if (length(all_files) == 0) return(tibble(msg = "No bet logs found."))

    map_dfr(all_files, function(f) {
      tryCatch(
        read_csv(f, col_types = cols(
          result    = col_character(),
          pnl       = col_double(),
          game_date = col_date(),
          log_date  = col_date(),
          .default  = col_guess()
        ), show_col_types = FALSE) %>%
          filter(result %in% c("W", "L")),
        error = function(e) tibble()
      )
    }) %>%
      select(any_of(c("sport", "log_date", "game_date", "home_team", "away_team",
                      "bet_type", "bet_team", "bet_line", "bet_ml",
                      "scaled_kelly", "result", "pnl"))) %>%
      # Deduplicate: same bet in multiple log files → keep smallest (capped) kelly
      group_by(sport, game_date, home_team, away_team, bet_type, bet_team, bet_line) %>%
      slice_min(scaled_kelly, n = 1, with_ties = FALSE) %>%
      ungroup() %>%
      arrange(desc(game_date))
  })

  # ── Reactive: arb detection from latest picks file ────────────────────────
  arb_picks <- reactive({
    picks_files <- Sys.glob("logs/daily_picks_*.csv")
    if (length(picks_files) == 0) return(tibble(Note = "No picks file found."))

    latest <- tail(sort(picks_files), 1)
    df <- tryCatch(
      read_csv(latest, col_types = cols(
        Odds     = col_double(),
        EV       = col_double(),
        Kelly    = col_double(),
        `Risk $` = col_double(),
        .default = col_character()
      ), show_col_types = FALSE),
      error = function(e) tibble(Note = "Could not load picks file.")
    )

    if (!"Home" %in% names(df)) return(tibble(Note = "Picks file missing expected columns."))

    # ML picks only — find games where both sides appear
    ml_picks <- df %>%
      filter(`Bet Type` == "ML") %>%
      mutate(game_key = paste(Date, Home, Away, sep = "|"))

    game_sides <- ml_picks %>%
      group_by(game_key, Date, Home, Away) %>%
      summarise(
        sides      = n(),
        picks_list = paste(Pick, collapse = " + "),
        odds_list  = paste(round(Odds, 2), collapse = " / "),
        books_list = paste(Book, collapse = " / "),
        sum_inv    = sum(1 / Odds, na.rm = TRUE),
        .groups    = "drop"
      ) %>%
      filter(sides >= 2) %>%
      mutate(arb_profit_pct = round((1 - sum_inv) * 100, 2)) %>%
      arrange(desc(arb_profit_pct))

    if (nrow(game_sides) == 0) {
      return(tibble(
        Note = "No arb opportunities in today's picks.",
        Tip  = "Both sides of a ML must appear in picks for an arb to exist."
      ))
    }

    game_sides %>%
      transmute(
        Date,
        Home,
        Away,
        `Both Picks`   = picks_list,
        Odds           = odds_list,
        Books          = books_list,
        `1/O1 + 1/O2`  = round(sum_inv, 4),
        `Arb Profit %` = arb_profit_pct,
        Verdict        = if_else(sum_inv < 1,
                                 "YES — LOCK IT",
                                 "EV overlap, not pure arb")
      )
  })

  # ── Tab 1: Paper Log ───────────────────────────────────────────────────────
  output$log_table <- renderDT({
    df <- logs() %>%
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


    # Character columns get select dropdowns; numeric keep range sliders.
    # Uses initComplete JS — compatible with all DT versions.
    char_idx <- paste(which(sapply(df, is.character)) - 1L, collapse = ",")

    dt <- datatable(df,
              filter     = "top",
              extensions = "Buttons",
              options    = list(
                dom        = "Bfrtip",
                pageLength = 25,
                buttons    = c("copy", "csv", "excel"),
                autoWidth  = TRUE,
                initComplete = JS(paste0("
                  function(settings, json) {
                    var charCols = [", char_idx, "];
                    var api = this.api();
                    charCols.forEach(function(colIdx) {
                      var col    = api.column(colIdx);
                      var header = $(col.header());
                      var input  = header.closest('thead').next('tfoot')
                                     .find('th').eq(colIdx).find('input');
                      if (input.length === 0) {
                        // filter='top' puts inputs in thead row 2
                        input = $(api.table().header()).find('tr:eq(1) th:eq('+colIdx+') input');
                      }
                      var parent = input.parent();
                      input.remove();
                      var sel = $('<select style=\"width:100%\"><option value=\"\">All</option></select>')
                        .appendTo(parent)
                        .on('change', function() {
                          var val = $.fn.dataTable.util.escapeRegex($(this).val());
                          col.search(val ? '^'+val+'$' : '', true, false).draw();
                        });
                      col.data().unique().sort().each(function(d) {
                        if (d !== null && d !== undefined && d !== '') {
                          sel.append('<option value=\"'+d+'\">'+d+'</option>');
                        }
                      });
                    });
                  }
                "))
              ))

    if ("Odds"   %in% names(df)) dt <- formatRound(dt,    "Odds",   digits = 2)
    if ("EV"     %in% names(df)) dt <- formatRound(dt,    "EV",     digits = 1)
    if ("Kelly"  %in% names(df)) dt <- formatRound(dt,    "Kelly",  digits = 4)
    if ("Risk $" %in% names(df)) dt <- formatCurrency(dt, "Risk $", currency = "$",
                                                       digits = 2, before = TRUE)
    dt
  })

  # ── Tab 3: Settled Bets ────────────────────────────────────────────────────
  output$settled_table <- renderDT({
    df <- settled_bets()
    if ("msg" %in% names(df)) return(datatable(df, options = list(dom = "t")))

    # Reference bankroll for converting kelly → dollars
    logs_df <- tryCatch(
      map_dfr(Sys.glob("logs/paper*log*.csv"),
              ~ read_csv(.x, col_types = cols(.default = col_guess()),
                         show_col_types = FALSE)),
      error = function(e) tibble()
    )
    ref_bankroll <- if (nrow(logs_df) > 0 && "starting_bankroll" %in% names(logs_df)) {
      logs_df$starting_bankroll[1]
    } else { 1000 }

    df_display <- df %>%
      mutate(
        `Log Date`   = if ("log_date" %in% names(.)) format(log_date, "%m/%d/%y")
                       else NA_character_,
        `Game Date`  = format(game_date, "%m/%d/%y"),
        Result       = if_else(result == "W", "W", "L"),
        `$W/L`       = round(pnl * ref_bankroll, 2),
        scaled_kelly = round(scaled_kelly, 5)
      ) %>%
      select(any_of(c("sport", "Log Date", "Game Date", "home_team", "away_team",
                      "bet_type", "bet_team", "bet_line", "bet_ml",
                      "scaled_kelly", "Result", "$W/L")))

    s_cols      <- names(df_display)
    idx_logdate <- which(s_cols == "Log Date")  - 1L
    idx_gamedate<- which(s_cols == "Game Date") - 1L
    s_char_idx <- paste(which(sapply(df_display, is.character)) - 1L, collapse = ",")

    dt <- datatable(df_display,
              filter     = "top",
              extensions = "Buttons",
              options    = list(
                dom        = "Bfrtip",
                pageLength = 50,
                buttons    = c("copy", "csv", "excel"),
                autoWidth  = FALSE,
                scrollX    = FALSE,
                order      = list(list(idx_gamedate, "desc"), list(idx_logdate, "desc")),
                columnDefs = list(
                  list(width = "75px",  targets = idx_logdate),
                  list(width = "75px",  targets = idx_gamedate),
                  list(width = "75px",  targets = which(s_cols == "sport")        - 1L),
                  list(width = "120px", targets = which(s_cols == "home_team")    - 1L),
                  list(width = "120px", targets = which(s_cols == "away_team")    - 1L),
                  list(width = "120px", targets = which(s_cols == "bet_team")     - 1L),
                  list(width = "60px",  targets = which(s_cols == "bet_type")     - 1L),
                  list(width = "55px",  targets = which(s_cols == "bet_ml")       - 1L),
                  list(width = "55px",  targets = which(s_cols == "bet_line")     - 1L),
                  list(width = "65px",  targets = which(s_cols == "scaled_kelly") - 1L),
                  list(width = "45px",  targets = which(s_cols == "Result")       - 1L),
                  list(width = "65px",  targets = which(s_cols == "$W/L")         - 1L)
                ),
                initComplete = JS(paste0("
                  function(settings, json) {
                    var charCols = [", s_char_idx, "];
                    var api = this.api();
                    charCols.forEach(function(colIdx) {
                      var col    = api.column(colIdx);
                      var input  = $(api.table().header()).find('tr:eq(1) th:eq('+colIdx+') input');
                      var parent = input.parent();
                      input.remove();
                      var sel = $('<select style=\"width:100%\"><option value=\"\">All</option></select>')
                        .appendTo(parent)
                        .on('change', function() {
                          var val = $.fn.dataTable.util.escapeRegex($(this).val());
                          col.search(val ? '^'+val+'$' : '', true, false).draw();
                        });
                      col.data().unique().sort().each(function(d) {
                        if (d !== null && d !== undefined && d !== '') {
                          sel.append('<option value=\"'+d+'\">'+d+'</option>');
                        }
                      });
                    });
                  }
                "))
              ))

    dt <- formatStyle(dt, "Result",
                      color      = styleEqual(c("W", "L"), c("#27AE60", "#E74C3C")),
                      fontWeight = "bold")
    dt <- formatStyle(dt, "$W/L",
                      color = styleInterval(0, c("#E74C3C", "#27AE60")))
    dt <- formatCurrency(dt, "$W/L", currency = "$", digits = 2, before = TRUE)
    dt
  })

  # ── Tab 4: Arb Alerts ─────────────────────────────────────────────────────
  output$arb_table <- renderDT({
    df <- arb_picks()
    if ("Note" %in% names(df) || "msg" %in% names(df)) {
      return(datatable(df, options = list(dom = "t")))
    }

    dt <- datatable(df,
              extensions = "Buttons",
              options    = list(
                dom        = "Bfrtip",
                pageLength = 25,
                buttons    = c("copy", "csv", "excel")
              ))

    dt <- formatStyle(dt, "Verdict",
                      backgroundColor = styleEqual(
                        "YES — LOCK IT", "#d4edda"
                      ),
                      fontWeight = styleEqual(
                        "YES — LOCK IT", "bold"
                      ))
    dt <- formatStyle(dt, "Arb Profit %",
                      color = styleInterval(0, c("#E74C3C", "#27AE60")))
    dt
  })

  # ── Tab 5: ROI Trend ───────────────────────────────────────────────────────
  output$roi_plot <- renderPlot({
    logs_df <- logs()
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
    positive <- plot_df$daily_roi_pct >= 0
    points(plot_df$date[positive],  plot_df$daily_roi_pct[positive],
           pch = 19, col = "#27AE60")
    points(plot_df$date[!positive], plot_df$daily_roi_pct[!positive],
           pch = 19, col = "#E74C3C")
  })
}

shinyApp(ui, server)
