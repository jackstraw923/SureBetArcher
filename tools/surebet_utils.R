# ============================================================
# surebet_utils.R — SureBet Tools Shared Utilities
# ============================================================
# Shared data loaders, constants, and helper functions used
# by all scripts in the tools/ directory.
#
# Usage: source("tools/surebet_utils.R") at the top of any
# tool script. Always run from the SureBet root directory:
#   setwd("C:/Users/jacks/OneDrive/Documents/SureBet")
#
# Does NOT require SureBet.R to be sourced first — loads
# everything it needs directly from the logs/ directory.
# ============================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(readr)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(glue)
})

# ── Constants ────────────────────────────────────────────────────────────────
SUREBET_DIR   <- "C:/Users/jacks/OneDrive/Documents/SureBet"
LOGS_DIR      <- file.path(SUREBET_DIR, "logs")
TOOLS_DIR     <- file.path(SUREBET_DIR, "tools")
REPORTS_DIR   <- file.path(TOOLS_DIR, "reports")   # output CSVs land here

# Create reports dir on first use
if (!dir.exists(REPORTS_DIR)) dir.create(REPORTS_DIR, recursive = TRUE)

BOOK_LABELS <- c(
  fanduel    = "FanDuel",
  draftkings = "DraftKings",
  espnbet    = "ESPN Bet",
  hardrockbet = "Hard Rock",
  fanatics   = "Fanatics",
  bet365     = "Bet365"
)

SPORT_LABELS <- c(
  NBA              = "NBA",
  NCAAB            = "NCAAB",
  NHL              = "NHL",
  "SOCCER-EPL"     = "Soccer - EPL",
  "SOCCER-BUND"    = "Soccer - Bundesliga",
  "SOCCER-SERA"    = "Soccer - Serie A",
  "SOCCER-LIGA"    = "Soccer - La Liga",
  "SOCCER-LIG1"    = "Soccer - Ligue 1",
  "SOCCER-MLS"     = "Soccer - MLS",
  "SOCCER-UCL"     = "Soccer - UCL",
  "SOCCER-UEL"     = "Soccer - UEL",
  "ATP - Indian Wells" = "ATP - Indian Wells",
  "WTA - Indian Wells" = "WTA - Indian Wells"
)

# ── Log file discovery ────────────────────────────────────────────────────────

#' List all log files of a given type, sorted oldest to newest
#' @param prefix  File prefix e.g. "bet_log", "spread_total_log", "paper_trading_log"
#' @param dir     Log directory (defaults to LOGS_DIR)
list_log_files <- function(prefix, dir = LOGS_DIR) {
  files <- list.files(dir, pattern = paste0("^", prefix, ".*\\.csv$"),
                      full.names = TRUE)
  sort(files)
}

# ── Log loaders ───────────────────────────────────────────────────────────────

#' Load and combine all paper trading log entries
load_paper_log <- function(dir = LOGS_DIR) {
  files <- list_log_files("paper_trading_log", dir)
  if (length(files) == 0) {
    message("No paper_trading_log files found in: ", dir)
    return(tibble())
  }
  map_dfr(files, ~ read_csv(.x, col_types = cols(
    date               = col_date(),
    starting_bankroll  = col_double(),
    total_risked       = col_double(),
    settled_pnl_kelly  = col_double(),
    settled_pnl_dollar = col_double(),
    ending_bankroll    = col_double(),
    daily_roi          = col_double(),
    cumulative_roi     = col_double(),
    wins               = col_integer(),
    losses             = col_integer(),
    unsettled          = col_integer()
  ), show_col_types = FALSE))
}

#' Load and combine all ML bet logs (NBA/NCAAB/NHL)
load_bet_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("bet_log", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, col_types = cols(
    sport        = col_character(),
    log_date     = col_date(),
    game_date    = col_date(),
    home_team    = col_character(),
    away_team    = col_character(),
    bookmaker_key = col_character(),
    bet_type     = col_character(),
    bet_team     = col_character(),
    bet_ml       = col_double(),
    raw_kelly    = col_double(),
    scaled_kelly = col_double(),
    result       = col_character(),
    pnl          = col_double(),
    .default     = col_guess()
  ), show_col_types = FALSE))
}

#' Load and combine all spread/total bet logs
load_spread_total_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("spread_total_log", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, col_types = cols(
    sport        = col_character(),
    log_date     = col_date(),
    game_date    = col_date(),
    home_team    = col_character(),
    away_team    = col_character(),
    bookmaker_key = col_character(),
    bet_type     = col_character(),
    bet_team     = col_character(),
    bet_line     = col_double(),
    bet_odds     = col_double(),
    raw_kelly    = col_double(),
    scaled_kelly = col_double(),
    result       = col_character(),
    pnl          = col_double(),
    .default     = col_guess()
  ), show_col_types = FALSE))
}

#' Load and combine all soccer bet logs
load_soccer_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("soccer_bet_log", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, show_col_types = FALSE,
                             col_types = cols(
                               game_date = col_date(),
                               log_date  = col_date(),
                               .default  = col_guess()
                             )))
}

#' Load and combine all tennis bet logs
load_tennis_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("tennis_bet_log", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, show_col_types = FALSE,
                             col_types = cols(
                               game_date = col_date(),
                               log_date  = col_date(),
                               .default  = col_guess()
                             )))
}

#' Load and combine all Challenger bet logs
load_challenger_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("challenger_picks", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, show_col_types = FALSE,
                             col_types = cols(
                               game_date = col_date(),
                               .default  = col_guess()
                             )))
}

#' Load and combine all MLB bet logs
load_mlb_logs <- function(dir = LOGS_DIR) {
  files <- list_log_files("mlb_bet_log", dir)
  if (length(files) == 0) return(tibble())
  map_dfr(files, ~ read_csv(.x, show_col_types = FALSE,
                             col_types = cols(
                               game_date = col_date(),
                               log_date  = col_date(),
                               .default  = col_guess()
                             )))
}

#' Load all settled bets across all sports into one combined tibble
#' Useful for cross-sport P&L and model calibration analysis
load_all_settled_bets <- function(dir = LOGS_DIR) {
  ml   <- load_bet_logs(dir)
  st   <- load_spread_total_logs(dir)
  soc  <- load_soccer_logs(dir)
  ten  <- load_tennis_logs(dir)
  cha  <- load_challenger_logs(dir)
  mlb  <- load_mlb_logs(dir)

  # Normalise to a common slim schema for cross-sport analysis
  slim <- function(df, sport_col = "sport") {
    if (nrow(df) == 0) return(tibble())
    df %>%
      filter(!is.na(result)) %>%
      select(any_of(c("sport", "sport_tournament", "log_date", "game_date",
                      "bet_team", "bet_ml", "scaled_kelly", "result", "pnl"))) %>%
      rename(sport = any_of(c("sport", "sport_tournament")))
  }

  bind_rows(slim(ml), slim(st), slim(soc), slim(ten), slim(cha), slim(mlb)) %>%
    filter(!is.na(result), result %in% c("W", "L")) %>%
    arrange(game_date)
}

# ── Helper functions ──────────────────────────────────────────────────────────

#' Format a number as a percentage string e.g. 0.1234 -> "12.3%"
fmt_pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), x * 100)

#' Format a dollar amount e.g. 1234.5 -> "$1,234.50"
fmt_dollar <- function(x) scales::dollar(x, accuracy = 0.01)

#' Summarise win rate and P&L for a set of settled bets
bet_summary <- function(df) {
  df %>%
    filter(result %in% c("W", "L")) %>%
    summarise(
      n_bets    = n(),
      wins      = sum(result == "W"),
      losses    = sum(result == "L"),
      win_rate  = round(wins / n_bets, 4),
      total_pnl = round(sum(pnl, na.rm = TRUE), 4),
      avg_pnl   = round(mean(pnl, na.rm = TRUE), 6),
      .groups   = "drop"
    )
}

#' Print a tidy section header to the console
section <- function(title) {
  width <- 60
  bar   <- paste(rep("─", width), collapse = "")
  cat("\n", bar, "\n", title, "\n", bar, "\n", sep = "")
}

cat("✅ surebet_utils.R loaded\n")
cat("   Logs dir:    ", LOGS_DIR,   "\n")
cat("   Reports dir: ", REPORTS_DIR, "\n\n")
