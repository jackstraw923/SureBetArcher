# SureBet v1.R 03/02/2026 - George Beason (using Perplexity)
# -*- coding: UTF-8 -*-
# Update and extension of BetSheet program

# ============================================================
# LIBRARIES
# ============================================================
library(tidyverse)
library(lubridate)
library(data.table)
library(readxl)
library(openxlsx)
library(oddsapiR)
library(jsonlite)
library(curl)
library(baseballr)
library(worldfootballR)
library(hoopR)
library(fastRhockey)

setwd("C:/Users/jacks/OneDrive/Documents/SureBet")
SUREBET_DIR <- "C:/Users/jacks/OneDrive/Documents/SureBet"  # master path anchor

# ============================================================
# RESULTS FETCHER — March 2, 2026
# ============================================================

# NBA results — direct from ESPN scoreboard (bypasses stale hoopR cache)
nba_results_raw <- fromJSON(
  "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=20260302"
)

nba_results <- map_dfr(
  seq_len(nrow(nba_results_raw$events)),
  function(i) {
    event <- nba_results_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    status <- comp$status[[1]]
    tibble(
      game_date  = as.Date(substr(event$date, 1, 10)),
      home_team  = teams$team$displayName[teams$homeAway == "home"],
      away_team  = teams$team$displayName[teams$homeAway == "away"],
      home_score = as.integer(teams$score[teams$homeAway == "home"]),
      away_score = as.integer(teams$score[teams$homeAway == "away"]),
      completed  = status$type$completed
    )
  }
)

# NHL results — parse the raw fetch we already ran
nhl_results <- map_dfr(
  seq_len(nrow(nhl_results_raw$events)),
  function(i) {
    event <- nhl_results_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    status <- comp$status[[1]]
    tibble(
      game_date  = as.Date(substr(event$date, 1, 10)),
      home_team  = teams$team$displayName[teams$homeAway == "home"],
      away_team  = teams$team$displayName[teams$homeAway == "away"],
      home_score = as.integer(teams$score[teams$homeAway == "home"]),
      away_score = as.integer(teams$score[teams$homeAway == "away"]),
      completed  = status$type$completed
    )
  }
)

# Preview both
cat("NBA games March 2:\n")
print(nba_results %>% filter(completed == TRUE))

cat("\nNHL games March 2:\n")
print(nhl_results %>% filter(completed == TRUE))
