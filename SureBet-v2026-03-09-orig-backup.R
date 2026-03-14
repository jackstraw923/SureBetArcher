# SureBet v1.R 03/02/2026 - George Beason (using Perplexity)
# -*- coding: UTF-8 -*-
# Update and extension of BetSheet program

# ============================================================
# Parking Lot, Notes, Comments
# ============================================================

# ── PARKING LOT ───────────────────────────────────────────────────────────────
# TODO (March 27): Wire MLB into combined Kelly + paper trading pipeline
#   1. Add value_mlb$raw_kelly and totals_mlb$raw_kelly to all_raw_kelly vector
#   2. Add MLB log to the combined paper trading settler
#   3. Flip MLB_SPORT_KEY to "baseball_mlb" and MLB_SEASON to 2026
#   4. Confirm fetch_mlb_standings() pulls live 2026 data successfully
# ─────────────────────────────────────────────────────────────────────────────

# ============================================================
# OPERATING RULES (Work in progress; nothing concrete yet)
# ============================================================

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
# API KEYS
# ============================================================
# Keys are stored in .Renviron and loaded automatically at session start.
# To edit: usethis::edit_r_environ()
#
# ODDS_API_KEY    → oddsapiR (toa_sports_odds) reads this automatically
# API_FOOTBALL_KEY → reserved for soccer section (worldfootballR / api-football)
#
# Verify keys are loaded:
# Sys.getenv("ODDS_API_KEY")
# Sys.getenv("API_FOOTBALL_KEY")


# ============================================================
# THE ODDS API - FETCH ALL SPORTS
# ============================================================
books  <- c("fanduel", "draftkings", "espnbet", "hardrockbet", "fanatics", "bet365")
sports <- c("basketball_nba", "basketball_ncaab", "icehockey_nhl",
            "soccer_epl", "soccer_germany_bundesliga", "soccer_italy_serie_a",
            "soccer_france_ligue_one", "soccer_spain_la_liga", "soccer_usa_mls",
            "soccer_uefa_champs_league", "soccer_uefa_europa_league")
# TODO (March 27): Add "baseball_mlb" here and remove the
# MLB supplemental fetch block (MLB_SPORT_KEY preseason workaround)


multi_odds <- map_dfr(
  sports,
  ~ suppressWarnings(
    toa_sports_odds(
      sport_key = .x,
      regions   = "us,us2",
      markets   = "h2h,spreads,totals"
    ) %>%
      mutate(sport_key = .x)
  )
)

# ============================================================
# Start runs at this point to avoid unnecessary calls
# ============================================================

multi_odds_filtered <- multi_odds %>%
  filter(bookmaker_key %in% books)

multi_odds_raw <- multi_odds_filtered

# ============================================================
# TEAM NAME CROSSWALK (expand as mismatches found)
# ============================================================
name_crosswalk <- tribble(
  ~toa_name,                          ~standard_name,
  # NBA
  "Los Angeles Clippers",             "LA Clippers",
  # NCAAB
  "Cleveland St Vikings",             "Cleveland State Vikings",
  "Coppin St Eagles",                 "Coppin State Eagles",
  "Delaware St Hornets",              "Delaware State Hornets",
  "IUPUI Jaguars",                    "IU Indianapolis Jaguars",
  "Maryland-Eastern Shore Hawks",     "Maryland Eastern Shore Hawks",
  "Montana St Bobcats",               "Montana State Bobcats",
  "Morgan St Bears",                  "Morgan State Bears",
  "N Colorado Bears",                 "Northern Colorado Bears",
  "Nicholls St Colonels",       "Nicholls Colonels",
  "Nicholls State Colonels",    "Nicholls Colonels", 
  "Norfolk St Spartans",              "Norfolk State Spartans",
  "Northwestern St Demons",           "Northwestern State Demons",
  "Portland St Vikings",              "Portland State Vikings",
  "Sacramento St Hornets",            "Sacramento State Hornets",
  "South Carolina St Bulldogs",       "South Carolina State Bulldogs",
  "Texas A&M-CC Islanders",           "Texas A&M-Corpus Christi Islanders"
  # NHL additions go here
  # Soccer additions go here
)

fix_team_names <- function(df, crosswalk) {
  df %>%
    mutate(
      home_team = coalesce(crosswalk$standard_name[match(home_team, crosswalk$toa_name)], home_team),
      away_team = coalesce(crosswalk$standard_name[match(away_team, crosswalk$toa_name)], away_team)
    )
}

multi_odds_filtered <- fix_team_names(multi_odds_raw, name_crosswalk)

# ============================================================
# SYSTEM CONSTANTS — all tunable parameters in one place
# ============================================================

# ── Portfolio / Kelly ──────────────────────────────────────────────────────────
BANKROLL_CAP       <- 0.20    # max combined Kelly exposure; raised from 0.10 (paper trading)
EV_CAP             <- 2.00    # sanity ceiling — reject implausibly large EV; calibrate after BT
EV_GATE            <- 0.0524  # Gate 1: minimum EV to consider a bet (5.24%)
# replaces hardcoded 0.05 in calc_value_bets AND ev_gate in calc_mlb_totals
MIN_BOOKS_FOR_A_TIER  <- 4    # books showing value for high-confidence tier flag
FREE_BET_MIN_ODDS     <- 2.50 # minimum decimal odds to deploy a free bet

# ── Bet Windows (time to expiration) ──────────────────────────────────────────
# Defines how early to "open a position" — analogous to DTE in options
# TODO: Enforce these in the odds fetch filter once window logic is built
BET_WINDOW_NBA_HRS    <- 48
BET_WINDOW_NCAAB_HRS  <- 24   # lines post later; tighter window appropriate
BET_WINDOW_NHL_HRS    <- 48
BET_WINDOW_MLB_HRS    <- 24   # daily starters often not confirmed until day-of
BET_WINDOW_SOCCER_HRS <- 72
BET_WINDOW_NFL_HRS    <- 72

# ── Delta / Hedge signals ──────────────────────────────────────────────────────
# HEDGE_TRIGGER_CLV: if line moves >15% in our favor since open_time,
# flag for hedge review — equivalent to delta threshold in options
HEDGE_TRIGGER_CLV  <- 0.15

# ── Spread model (log-odds → points conversion) ───────────────────────────────
# k calibrated per sport scoring distribution; revisit after backtesting
K_SPREAD_NBA       <-  7.0    # ~7 pts per log-odds unit
K_SPREAD_NCAAB     <-  6.5
K_SPREAD_NHL       <-  3.2    # goals, not points
# K_SPREAD_MLB     <-  NA     # MLB uses run-line model, not log-odds spread — TODO

# ── League average scoring (totals model) ─────────────────────────────────────
# Update these at start of each season
LEAGUE_AVG_NBA     <- 112.5   # pts/game per team
LEAGUE_AVG_NCAAB   <-  75.0
LEAGUE_AVG_NHL     <-   3.1   # goals/game per team

# ── Spread / Total edge minimums ──────────────────────────────────────────────
MIN_SPREAD_EDGE_PTS  <- 3.0   # pts of model edge required to flag a spread bet
MIN_TOTAL_EDGE_PTS   <- 3.0   # pts of model edge required to flag an over/under

# ── Pythagorean exponents ──────────────────────────────────────────────────────
# Sport-specific; dynamic formulas used where available (see standings blocks)
PYTH_EXP_NBA       <- 14.3    # Morey exponent; explore dynamic formula post-BT
PYTH_EXP_NCAAB_K   <-  0.287  # PythagenPat k-factor for dynamic exponent
PYTH_EXP_NHL_K     <-  0.458  # PythagenPuck k-factor
PYTH_EXP_MLB       <-  0.287  # Pythagenpat
PYTH_EXP_MLB_BSR   <-  0.285  # BaseRuns Pythagorean exponent
# Starting values near the Maher/Dixon-Coles literature range of 1.25–1.35.
# All initialized to DEFAULT; calibrate individually after backtesting.
PYTH_SOCCER_EPL  <- 1.30
PYTH_SOCCER_BUND <- 1.28
PYTH_SOCCER_SERA <- 1.28
PYTH_SOCCER_LIGA <- 1.30
PYTH_SOCCER_LIG1 <- 1.28
PYTH_SOCCER_MLS  <- 1.25  # MLS tends slightly lower due to parity
PYTH_SOCCER_UCL  <- 1.32  # UCL scoring distribution skews slightly higher
PYTH_SOCCER_UEL  <- 1.30
PYTH_SOCCER_DEFAULT <- 1.30   # fallback when league-specific exponent unavailable

# ── MLB-specific ───────────────────────────────────────────────────────────────
MLB_SPORT_KEY  <- "baseball_mlb_preseason"  # flip to "baseball_mlb" on March 27
MLB_SEASON     <- 2025                       # flip to 2026 on March 27
HFA_MLB        <- 0.025        # home field advantage (~2.5%)
MLB_SIGMA      <- 2.5          # normal CDF sigma for totals model (runs); calibrate post-BT
MLB_BSR_G1     <- 40           # games threshold: below = max BaseRuns weight
MLB_BSR_G2     <- 100          # games threshold: above = max Pythagorean weight
MLB_BSR_WMAX   <- 0.70         # BaseRuns weight early season
MLB_BSR_WMIN   <- 0.30         # BaseRuns weight late season

# ── Position lifecycle ─────────────────────────────────────────────────────
POSITION_STATES <- c("IDENTIFIED", "OPEN", "LIVE",
                     "HEDGED", "CLOSED", "SETTLED",
                     "EXPIRED", "VOID")

VALID_TRANSITIONS <- list(
  IDENTIFIED = c("OPEN", "EXPIRED", "VOID"),
  OPEN       = c("LIVE", "VOID"),
  LIVE       = c("HEDGED", "CLOSED", "SETTLED", "VOID"),
  HEDGED     = c("SETTLED", "VOID"),
  CLOSED     = character(0),   # terminal — cashout processed
  SETTLED    = character(0),   # terminal — game complete
  EXPIRED    = character(0),   # terminal — never placed
  VOID       = character(0)    # terminal — cancelled/postponed
)

# ── Hedge / Close trigger thresholds ──────────────────────────────────────
HEDGE_TRIGGER_CLV <- 0.15   # line moved ≥15% in our favor → look for middle
CLOSE_TRIGGER_CLV <- 0.10   # line moved ≥10% but no middle → cash out
CLOSE_MIN_PROFIT  <- 0.03   # don't close for less than 3% return on stake

# ============================================================
# POSITION LIFECYCLE ENGINE
# ============================================================

# ── 1. position_id generator ───────────────────────────────────────────────
# Deterministic key — same bet always gets the same ID
# Lets you safely re-run the script without creating duplicates
make_position_id <- function(sport, game_date, home_team,
                             away_team, value_side, bookmaker_key) {
  paste(sport, game_date, home_team, away_team,
        value_side, bookmaker_key, sep = "|")
}

# ── 2. Transition validator ────────────────────────────────────────────────
transition_position <- function(log_df, position_id, new_status,
                                extra_fields = list()) {
  current <- log_df$status[log_df$position_id == position_id]
  
  if (length(current) == 0) {
    warning("position_id not found: ", position_id)
    return(log_df)
  }
  
  valid <- VALID_TRANSITIONS[[ current ]]
  if (!new_status %in% valid) {
    warning(sprintf(
      "Invalid transition: %s → %s for position %s",
      current, new_status, position_id
    ))
    return(log_df)
  }
  
  terminal <- c("CLOSED", "SETTLED", "EXPIRED", "VOID")
  
  log_df %>%
    mutate(
      status      = if_else(position_id == !!position_id,
                            new_status, status),
      settle_time = case_when(
        position_id == !!position_id & new_status %in% terminal
        ~ Sys.time(),
        TRUE ~ settle_time
      ),
      # Hedge leg fields — populated only on IDENTIFIED → HEDGED transition
      hedge_time     = if_else(
        position_id == !!position_id & new_status == "HEDGED",
        coalesce(extra_fields$hedge_time,   hedge_time), hedge_time),
      hedge_book     = if_else(
        position_id == !!position_id & new_status == "HEDGED",
        coalesce(extra_fields$hedge_book,   hedge_book), hedge_book),
      hedge_ml       = if_else(
        position_id == !!position_id & new_status == "HEDGED",
        coalesce(extra_fields$hedge_ml,     hedge_ml),   hedge_ml),
      hedge_stake    = if_else(
        position_id == !!position_id & new_status == "HEDGED",
        coalesce(extra_fields$hedge_stake,  hedge_stake), hedge_stake),
      clv_at_action  = if_else(
        position_id == !!position_id & new_status %in% c("HEDGED","CLOSED"),
        coalesce(extra_fields$clv_at_action, clv_at_action), clv_at_action),
      # Close leg fields — populated only on LIVE → CLOSED transition
      cashout_value  = if_else(
        position_id == !!position_id & new_status == "CLOSED",
        coalesce(extra_fields$cashout_value, cashout_value), cashout_value),
      pnl            = case_when(
        position_id == !!position_id & new_status == "CLOSED"
        ~ extra_fields$cashout_value - stake,   # immediate P&L on close
        TRUE ~ pnl
      )
    )
}

# ── 3. Batch status refresher — run at top of every session ───────────────
# Sweeps the persisted log and auto-advances clock-driven transitions
refresh_position_statuses <- function(log_df) {
  now <- Sys.time()
  log_df %>%
    mutate(
      status = case_when(
        # IDENTIFIED with no placement before game start → EXPIRED
        status == "IDENTIFIED" & now >= game_start ~ "EXPIRED",
        # OPEN → LIVE the moment the game starts
        status == "OPEN"       & now >= game_start ~ "LIVE",
        # Everything else — no automatic advance beyond LIVE
        # (HEDGED, CLOSED, SETTLED require human confirmation or settler block)
        TRUE ~ status
      )
    )
}

# ── 4. Action checker — returns a flag table, never modifies log ───────────
# Run once per session against all LIVE positions
# Returns three tiers: HEDGE candidates, CLOSE candidates, HOLD
check_position_actions <- function(log_df, current_odds_df) {
  live <- log_df %>% filter(status == "LIVE")
  if (nrow(live) == 0) {
    cat("No LIVE positions to check.\n")
    return(invisible(NULL))
  }
  
  live %>%
    left_join(
      current_odds_df %>%
        select(home_team, away_team, bookmaker_key,
               value_side, current_ml = bet_ml),
      by = c("home_team", "away_team", "bookmaker_key", "value_side")
    ) %>%
    mutate(
      clv_now         = (current_ml - bet_ml) / abs(bet_ml),
      min_close_pnl   = stake * CLOSE_MIN_PROFIT,
      potential_close = (cashout_value - stake),        # filled by book API later
      action = case_when(
        clv_now >= HEDGE_TRIGGER_CLV                    ~ "HEDGE",
        clv_now >= CLOSE_TRIGGER_CLV                    ~ "CLOSE",
        TRUE                                            ~ "HOLD"
      )
    ) %>%
    select(position_id, sport, game_date, home_team, away_team,
           value_side, bet_ml, current_ml, clv_now, action,
           stake, bookmaker_key) %>%
    arrange(desc(clv_now))
}

# ── 5. P&L calculator — called by settler, works across all terminal states ─
calc_position_pnl <- function(log_df) {
  log_df %>%
    mutate(
      pnl = case_when(
        # Closed early — cashout already recorded in transition_position()
        status == "CLOSED"  ~ cashout_value - stake,
        
        # Hedged — net P&L across both legs
        # If middle hit (both legs win), pnl = both payouts - both stakes
        # If one leg wins, pnl = winning payout - both stakes
        status == "SETTLED" & !is.na(hedge_stake) ~
          (result * bet_ml * stake) +
          (hedge_result * hedge_ml * hedge_stake) -
          (stake + hedge_stake),
        
        # Held to settlement — standard
        status == "SETTLED" & is.na(hedge_stake) ~
          if_else(result == 1,
                  stake * (bet_ml - 1),   # decimal odds profit
                  -stake),
        
        # All terminal non-settled states
        status %in% c("EXPIRED", "VOID") ~ 0,
        
        TRUE ~ NA_real_
      )
    )
}



# ── 6. ML bet log writer ──────────────────────────────────────────────────────
# Writes IDENTIFIED positions to a dated CSV.
# Re-run safe: if today's file already exists, only NEW position_ids are appended.
# Positions already advanced to OPEN/LIVE/SETTLED are never overwritten.
write_bet_log <- function(df, log_dir = "logs") {
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  log_path <- file.path(log_dir, paste0("bet_log_", Sys.Date(), ".csv"))
  
  ml_cols <- c("sport", "log_date", "game_date", "open_time",
               "home_team", "away_team", "bookmaker_key",
               "value_side", "bet_team", "bet_ml", "bet_ev", "bet_edge", "implied_prob",
               "raw_kelly", "scaled_kelly",
               "position_id", "status", "placed_time", "game_start", "settle_time",
               "stake", "result", "cashout_value",
               "hedge_time", "hedge_book", "hedge_ml", "hedge_stake", "hedge_result",
               "clv_at_action", "pnl")
  
  new_rows <- df %>%
    mutate(log_date = Sys.Date()) %>%
    select(any_of(ml_cols))
  
  if (file.exists(log_path)) {
    existing <- read_csv(log_path,
                         col_types = cols(result    = col_character(),
                                          pnl       = col_double(),
                                          game_date = col_date(),
                                          log_date  = col_date(),
                                          .default  = col_guess()),
                         show_col_types = FALSE) %>%
      mutate(result = as.character(result))   # ← ADD: coerce legacy double NA to character NA
    new_only <- new_rows %>% filter(!position_id %in% existing$position_id)
    if (nrow(new_only) > 0) {
      write_csv(bind_rows(existing, new_only), log_path)
      cat(sprintf("✅ Bet log updated: %d new positions → %s\n", nrow(new_only), log_path))
    } else {
      cat(sprintf("ℹ️  Bet log unchanged — all %d positions already present\n", nrow(new_rows)))
    }
  } else {
    write_csv(new_rows, log_path)
    cat(sprintf("✅ Bet log created: %d ML positions → %s\n", nrow(new_rows), log_path))
  }
  invisible(log_path)
}

# ── 7. Spread / Total log writer ─────────────────────────────────────────────
write_spread_total_log <- function(df, log_dir = "logs") {
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  log_path <- file.path(log_dir, paste0("spread_total_log_", Sys.Date(), ".csv"))
  
  st_cols <- c("sport", "log_date", "game_date", "open_time",
               "home_team", "away_team", "bookmaker_key",
               "bet_type", "bet_team", "bet_line", "bet_odds",
               "bet_edge_pts", "bet_edge", "implied_prob",
               "raw_kelly", "scaled_kelly",
               "position_id", "status", "placed_time", "game_start", "settle_time",
               "stake", "result", "cashout_value",
               "hedge_time", "hedge_book", "hedge_ml", "hedge_stake", "hedge_result",
               "clv_at_action", "pnl")
  
  new_rows <- df %>%
    mutate(log_date = Sys.Date()) %>%
    select(any_of(st_cols))
  
  if (file.exists(log_path)) {
    existing <- read_csv(log_path,
                         col_types = cols(result    = col_character(),
                                          pnl       = col_double(),
                                          game_date = col_date(),
                                          log_date  = col_date(),
                                          .default  = col_guess()),
                         show_col_types = FALSE)
    new_only <- new_rows %>% filter(!position_id %in% existing$position_id)
    if (nrow(new_only) > 0) {
      write_csv(bind_rows(existing, new_only), log_path)
      cat(sprintf("✅ Spread/total log updated: %d new positions → %s\n", nrow(new_only), log_path))
    } else {
      cat(sprintf("ℹ️  Spread/total log unchanged — all %d positions already present\n", nrow(new_rows)))
    }
  } else {
    write_csv(new_rows, log_path)
    cat(sprintf("✅ Spread/total log created: %d spread/total positions → %s\n", nrow(new_rows), log_path))
  }
  invisible(log_path)
}

# ============================================================
# NBA - STANDINGS + SCHEDULE
# ============================================================
nba_schedule <- load_nba_schedule(seasons = 2026)

nba_standings <- nba_leaguestandings(
  league_id   = "00",
  season      = "2025-26",
  season_type = "Regular Season"
)$Standings %>%
  mutate(
    across(c(WINS, LOSSES, WinPCT, PointsPG, OppPointsPG, DiffPointsPG,
             PlayoffRank, LeagueRank), as.numeric),
    team = paste(TeamCity, TeamName)
  )

nba_pts <- nba_schedule %>%
  filter(status_type_completed == TRUE) %>%
  select(team = home_display_name, pts_for = home_score, pts_against = away_score) %>%
  bind_rows(
    nba_schedule %>%
      filter(status_type_completed == TRUE) %>%
      select(team = away_display_name, pts_for = away_score, pts_against = home_score)
  ) %>%
  group_by(team) %>%
  summarise(
    games_played      = n(),
    total_pts_for     = sum(pts_for),
    total_pts_against = sum(pts_against)
  )

nba_standings <- nba_standings %>%
  left_join(nba_pts, by = "team") %>%
  mutate(
    actual_winpct = WINS / (WINS + LOSSES),
    pyth_exp_143  = total_pts_for^14.3 / (total_pts_for^14.3 + total_pts_against^14.3),
    vs_pyth_143   = actual_winpct - pyth_exp_143
  )

# Fetch pace + offensive/defensive ratings for the two-method totals model.
# nba_leaguedashteamstats() hits stats.nba.com via hoopR — no API key needed.
# Verify column names with: names(nba_leaguedashteamstats(season="2025-26", per_mode_simple="PerGame", measure_type_simple="Advanced"))
nba_adv <- nba_leaguedashteamstats(
  league_id    = "00",
  season       = "2025-26",
  season_type  = "Regular Season",
  per_mode     = "PerGame",
  measure_type = "Advanced"
)$LeagueDashTeamStats %>%
  mutate(across(c(PACE, OFF_RATING, DEF_RATING), as.numeric)) %>%
  select(team       = TEAM_NAME,
         pace       = PACE,
         off_rating = OFF_RATING,
         def_rating = DEF_RATING)

# Attach pace/ratings and per-game scoring to standings
nba_standings <- nba_standings %>%
  left_join(nba_adv, by = "team") %>%
  mutate(
    apf = PointsPG,       # avg pts scored per game
    apa = OppPointsPG     # avg pts allowed per game
  )


# ============================================================
# NBA - GAME-LEVEL ODDS TABLE
# ============================================================
odds_nba <- multi_odds_filtered %>%
  filter(sport_key == "basketball_nba") %>%
  mutate(
    game_date = as.Date(
      format(with_tz(ymd_hms(commence_time), "America/New_York"), "%Y-%m-%d")
    )
  )

h2h <- odds_nba %>%
  filter(market_key == "h2h") %>%
  mutate(side = if_else(outcomes_name == home_team, "home_ml", "away_ml")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price) %>%
  pivot_wider(names_from = side, values_from = outcomes_price,
              values_fn = first) %>%                          # <-- collapses duplicates
  mutate(across(c(home_ml, away_ml), as.numeric))

spreads <- odds_nba %>%
  filter(market_key == "spreads") %>%
  mutate(side = if_else(outcomes_name == home_team, "home", "away")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_spread_{.value}",
              values_fn = first) %>%                          # <-- collapses duplicates
  mutate(across(contains("spread"), as.numeric))

totals <- odds_nba %>%
  filter(market_key == "totals") %>%
  mutate(side = if_else(outcomes_name == "Over", "over", "under")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_{.value}",
              values_fn = first) %>%                          # <-- collapses duplicates
  mutate(across(c(over_outcomes_price, under_outcomes_price,
                  over_outcomes_point, under_outcomes_point), as.numeric))

odds_nba_wide <- h2h %>%
  left_join(spreads, by = c("game_date", "home_team", "away_team", "bookmaker_key")) %>%
  left_join(totals,  by = c("game_date", "home_team", "away_team", "bookmaker_key"))

nba_game_start <- odds_nba %>%
  distinct(game_date, home_team, away_team,
           game_start = as.POSIXct(commence_time, tz = "UTC")) %>%
  group_by(game_date, home_team, away_team) %>%
  slice(1) %>%
  ungroup()

odds_nba_wide <- odds_nba_wide %>%
  left_join(nba_game_start, by = c("game_date", "home_team", "away_team"))

nba_games <- odds_nba_wide %>%
  left_join(
    nba_schedule %>%
      filter(!home_display_name %in% c("TBD"), game_date >= Sys.Date()) %>%
      select(game_date, home_display_name, away_display_name),
    by = c("game_date",
           "home_team" = "home_display_name",
           "away_team" = "away_display_name")
  ) %>%
  left_join(
    nba_standings %>%
      select(team, WINS, LOSSES, actual_winpct, pyth_exp_143, vs_pyth_143,
             Conference, DiffPointsPG),
    by = c("home_team" = "team")
  ) %>%
  rename_with(~ paste0("home_", .),
              c(WINS, LOSSES, actual_winpct, pyth_exp_143, vs_pyth_143,
                Conference, DiffPointsPG)) %>%
  left_join(
    nba_standings %>%
      select(team, WINS, LOSSES, actual_winpct, pyth_exp_143, vs_pyth_143,
             Conference, DiffPointsPG),
    by = c("away_team" = "team")
  ) %>%
  rename_with(~ paste0("away_", .),
              c(WINS, LOSSES, actual_winpct, pyth_exp_143, vs_pyth_143,
                Conference, DiffPointsPG))

# ============================================================
# NCAAB - STANDINGS + PYTHAGOREAN (PythagenPat dynamic exponent)
# ============================================================
ncaab_box_raw <- load_mbb_team_box(seasons = 2026)

ncaab_standings <- ncaab_box_raw %>%
  filter(!is.na(team_score), !is.na(opponent_team_score)) %>%
  group_by(team_id, team_display_name, team_abbreviation) %>%
  summarise(
    gamesPlayed = n(),
    ptsFor      = sum(team_score,          na.rm = TRUE),
    ptsAgainst  = sum(opponent_team_score, na.rm = TRUE),
    wins        = sum(team_winner,         na.rm = TRUE),
    .groups     = "drop"
  ) %>%
  filter(gamesPlayed >= 15) %>%
  mutate(
    actual_winpct    = wins / gamesPlayed,
    pts_pg           = (ptsFor + ptsAgainst) / gamesPlayed,
    pyth_exp_dynamic = pts_pg^0.287,
    pyth_winpct      = ptsFor^pyth_exp_dynamic /
      (ptsFor^pyth_exp_dynamic + ptsAgainst^pyth_exp_dynamic),
    vs_pyth          = actual_winpct - pyth_winpct
  )

# ============================================================
# NCAAB - RANKINGS (AP Top 25 + Coaches Poll)
# ============================================================
ncaab_rankings_raw <- fromJSON(
  "http://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/rankings"
)

extract_poll <- function(poll_pattern, rank_col) {
  poll_row <- ncaab_rankings_raw$rankings %>%
    filter(str_detect(name, poll_pattern))
  if (nrow(poll_row) == 0) return(
    tibble(!!rank_col := integer(0), team_display_name = character(0))
  )
  ranks_df <- poll_row %>% pull(ranks) %>% .[[1]]
  tibble(
    !!rank_col        := ranks_df$current,
    team_display_name  = paste(ranks_df$team$location, ranks_df$team$name)
  )
}

ncaab_ap      <- extract_poll("AP Top 25",    "ap_rank")
ncaab_coaches <- extract_poll("Coaches Poll", "coaches_rank")

ncaab_standings <- ncaab_standings %>%
  left_join(ncaab_ap,      by = "team_display_name") %>%
  left_join(ncaab_coaches, by = "team_display_name")

# ============================================================
# NCAAB - SCHEDULE (today, all D1 games)
# ============================================================
ncaab_sched_raw <- fromJSON(paste0(
  "http://site.api.espn.com/apis/site/v2/sports/basketball/",
  "mens-college-basketball/scoreboard?groups=50&limit=200"
))

ncaab_schedule <- map_dfr(
  seq_len(nrow(ncaab_sched_raw$events)),
  function(i) {
    event <- ncaab_sched_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    tibble(
      game_date = as.Date(substr(event$date, 1, 10)),
      home_team = teams$team$displayName[teams$homeAway == "home"],
      away_team = teams$team$displayName[teams$homeAway == "away"]
    )
  }
)

# ============================================================
# NCAAB - ODDS (from master odds table)
# ============================================================
# AFTER — add commence_time to the select
ncaab_odds <- multi_odds_filtered %>%
  filter(sport_key == "basketball_ncaab") %>%
  mutate(game_date = as.Date(commence_time)) %>%
  select(game_date, commence_time, home_team, away_team,
         bookmaker_key, market_key,
         outcomes_name, outcomes_price, outcomes_point)

# ============================================================
# NCAAB - GAME-LEVEL ODDS TABLE
# ============================================================

h2h_ncaab <- ncaab_odds %>%
  filter(market_key == "h2h") %>%
  mutate(side = case_when(
    outcomes_name == home_team ~ "home_ml",
    outcomes_name == away_team ~ "away_ml",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(side)) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price) %>%
  pivot_wider(names_from = side, values_from = outcomes_price)

spreads_ncaab <- ncaab_odds %>%
  filter(market_key == "spreads") %>%
  mutate(side = case_when(
    outcomes_name == home_team ~ "home",
    outcomes_name == away_team ~ "away",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(side)) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_spread_{.value}")


totals_ncaab <- ncaab_odds %>%
  filter(market_key == "totals") %>%
  mutate(side = if_else(outcomes_name == "Over", "over", "under")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_{.value}")

odds_ncaab_wide <- h2h_ncaab %>%
  left_join(spreads_ncaab, by = c("game_date", "home_team", "away_team", "bookmaker_key")) %>%
  left_join(totals_ncaab,  by = c("game_date", "home_team", "away_team", "bookmaker_key"))

ncaab_game_start <- ncaab_odds %>%
  distinct(game_date, home_team, away_team,
           game_start = as.POSIXct(commence_time, tz = "UTC")) %>%
  group_by(game_date, home_team, away_team) %>%
  slice(1) %>%
  ungroup()

odds_ncaab_wide <- odds_ncaab_wide %>%
  left_join(ncaab_game_start, by = c("game_date", "home_team", "away_team"))


ncaab_games <- odds_ncaab_wide %>%
  left_join(
    ncaab_schedule %>%
      filter(game_date >= Sys.Date()) %>%
      select(game_date, home_team, away_team),
    by = c("game_date", "home_team", "away_team")
  ) %>%
  left_join(
    ncaab_standings %>%
      select(team_display_name, gamesPlayed, wins,
             actual_winpct, pyth_winpct, vs_pyth,
             ap_rank, coaches_rank),
    by = c("home_team" = "team_display_name")
  ) %>%
  rename_with(~ paste0("home_", .),
              c(gamesPlayed, wins, actual_winpct,
                pyth_winpct, vs_pyth, ap_rank, coaches_rank)) %>%
  left_join(
    ncaab_standings %>%
      select(team_display_name, gamesPlayed, wins,
             actual_winpct, pyth_winpct, vs_pyth,
             ap_rank, coaches_rank),
    by = c("away_team" = "team_display_name")
  ) %>%
  rename_with(~ paste0("away_", .),
              c(gamesPlayed, wins, actual_winpct,
                pyth_winpct, vs_pyth, ap_rank, coaches_rank))

glimpse(ncaab_games)

# ============================================================
# NHL - STANDINGS + PYTHAGOREAN (PythagenPuck dynamic exponent)
# ============================================================
nhl_standings_raw <- fromJSON("https://api-web.nhle.com/v1/standings/now")

nhl_standings <- nhl_standings_raw$standings %>%
  as_tibble() %>%
  mutate(
    team   = paste(placeName$default, teamCommonName$default),
    abbrev = teamAbbrev$default
  ) %>%
  select(-placeName, -teamName, -teamCommonName, -teamAbbrev) %>%
  mutate(
    team = case_when(
      abbrev == "NYI" ~ "New York Islanders",
      abbrev == "NYR" ~ "New York Rangers",
      TRUE ~ team
    ),
    actual_winpct    = wins / gamesPlayed,
    goals_pg         = (goalFor + goalAgainst) / gamesPlayed,
    pyth_exp_dynamic = goals_pg^0.458,
    pyth_exp_dyn     = goalFor^pyth_exp_dynamic /
      (goalFor^pyth_exp_dynamic + goalAgainst^pyth_exp_dynamic),
    vs_pyth_dyn      = actual_winpct - pyth_exp_dyn
  )

# ============================================================
# NHL - SCHEDULE (current week)
# ============================================================
nhl_schedule_raw <- fromJSON("https://api-web.nhle.com/v1/schedule/now")

nhl_schedule <- nhl_schedule_raw$gameWeek %>%
  select(date, games) %>%
  unnest(games) %>%
  as_tibble() %>%
  mutate(
    home_team = paste(homeTeam$placeName[["default"]], homeTeam$commonName[["default"]]),
    away_team = paste(awayTeam$placeName[["default"]], awayTeam$commonName[["default"]]),
    game_date = as.Date(date)
  ) %>%
  select(game_date, home_team, away_team)

# ============================================================
# NHL - GAME-LEVEL ODDS TABLE
# ============================================================
odds_nhl <- multi_odds_filtered %>%
  filter(sport_key == "icehockey_nhl") %>%
  mutate(
    game_date = as.Date(
      format(with_tz(ymd_hms(commence_time), "America/New_York"), "%Y-%m-%d")
    )
  )

h2h_nhl <- odds_nhl %>%
  filter(market_key == "h2h") %>%
  mutate(side = if_else(outcomes_name == home_team, "home_ml", "away_ml")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price) %>%
  pivot_wider(names_from = side, values_from = outcomes_price)

spreads_nhl <- odds_nhl %>%
  filter(market_key == "spreads") %>%
  mutate(side = if_else(outcomes_name == home_team, "home", "away")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_spread_{.value}")

totals_nhl <- odds_nhl %>%
  filter(market_key == "totals") %>%
  mutate(side = if_else(outcomes_name == "Over", "over", "under")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_{.value}")

odds_nhl_wide <- h2h_nhl %>%
  left_join(spreads_nhl, by = c("game_date", "home_team", "away_team", "bookmaker_key")) %>%
  left_join(totals_nhl,  by = c("game_date", "home_team", "away_team", "bookmaker_key"))

nhl_game_start <- odds_nhl %>%
  distinct(game_date, home_team, away_team,
           game_start = as.POSIXct(commence_time, tz = "UTC")) %>%
  group_by(game_date, home_team, away_team) %>%
  slice(1) %>%
  ungroup()

odds_nhl_wide <- odds_nhl_wide %>%
  left_join(nhl_game_start, by = c("game_date", "home_team", "away_team"))

nhl_games <- odds_nhl_wide %>%
  left_join(
    nhl_schedule %>%
      filter(game_date >= Sys.Date()) %>%
      select(game_date, home_team, away_team),
    by = c("game_date", "home_team", "away_team")
  ) %>%
  left_join(
    nhl_standings %>%
      select(team, wins, losses, otLosses, actual_winpct,
             pyth_exp_dyn, vs_pyth_dyn, conferenceName, goalDifferential),
    by = c("home_team" = "team")
  ) %>%
  rename_with(~ paste0("home_", .),
              c(wins, losses, otLosses, actual_winpct,
                pyth_exp_dyn, vs_pyth_dyn, conferenceName, goalDifferential)) %>%
  left_join(
    nhl_standings %>%
      select(team, wins, losses, otLosses, actual_winpct,
             pyth_exp_dyn, vs_pyth_dyn, conferenceName, goalDifferential),
    by = c("away_team" = "team")
  ) %>%
  rename_with(~ paste0("away_", .),
              c(wins, losses, otLosses, actual_winpct,
                pyth_exp_dyn, vs_pyth_dyn, conferenceName, goalDifferential))

# ============================================================
# SOCCER PIPELINE CORE
# ============================================================

# 1) League config (TOA sport_keys + FotMob league IDs + exponents)
SOCCER_LEAGUES <- tribble(
  ~sport_key,                        ~league_label, ~fotmob_id, ~pyth_exp,
  "soccer_epl",                      "EPL",          47,         PYTH_SOCCER_EPL,
  "soccer_germany_bundesliga",       "BUND",         54,         PYTH_SOCCER_BUND,
  "soccer_italy_serie_a",            "SERA",         55,         PYTH_SOCCER_SERA,
  "soccer_spain_la_liga",            "LIGA",         87,         PYTH_SOCCER_LIGA,
  "soccer_france_ligue_one",         "LIG1",         53,         PYTH_SOCCER_LIG1,
  "soccer_usa_mls",                  "MLS",         130,         PYTH_SOCCER_MLS,
  "soccer_uefa_champs_league",       "UCL",          42,         PYTH_SOCCER_UCL,
  "soccer_uefa_europa_league",       "UEL",          73,         PYTH_SOCCER_UEL
)


# 2) Name mapping (TOA → FotMob) ONLY where they differ
SOCCER_NAME_MAP <- tribble(
  ~toa_name,                    ~league,  ~fotmob_name,
  # ── BUND ──────────────────────────────────────────────
  "1. FC Heidenheim",           "BUND",   "FC Heidenheim",
  "Bayern Munich",              "BUND",   "Bayern München",
  "Borussia Monchengladbach",   "BUND",   "Borussia Mönchengladbach",
  "FC St. Pauli",               "BUND",   "St. Pauli",
  "FSV Mainz 05",               "BUND",   "Mainz 05",
  "SC Freiburg",                "BUND",   "Freiburg",
  "TSG Hoffenheim",             "BUND",   "Hoffenheim",
  "VfL Wolfsburg",              "BUND",   "Wolfsburg",
  # ── EPL ───────────────────────────────────────────────
  "Bournemouth",                "EPL",    "AFC Bournemouth",
  "Brighton and Hove Albion",   "EPL",    "Brighton & Hove Albion",
  # ── LIG1 ──────────────────────────────────────────────
  "AS Monaco",                  "LIG1",   "Monaco",
  "Paris Saint Germain",        "LIG1",   "Paris Saint-Germain",
  "RC Lens",                    "LIG1",   "Lens",
  "Paris FC",                   "LIG1",   "Paris FC",
  # ── LIGA ──────────────────────────────────────────────
  "Alavés",                     "LIGA",   "Deportivo Alaves",
  "Athletic Bilbao",            "LIGA",   "Athletic Club",
  "Atlético Madrid",            "LIGA",   "Atletico Madrid",
  "CA Osasuna",                 "LIGA",   "Osasuna",
  "Oviedo",                     "LIGA",   "Real Oviedo",
  "Elche CF",                   "LIGA",   "Elche",
  # ── MLS ───────────────────────────────────────────────
  "Atlanta United FC",          "MLS",    "Atlanta United",
  "CF Montréal",                "MLS",    "CF Montreal",
  "Chicago Fire",               "MLS",    "Chicago Fire FC",
  "Columbus Crew SC",           "MLS",    "Columbus Crew",
  "D.C. United",                "MLS",    "DC United",
  "Houston Dynamo",             "MLS",    "Houston Dynamo FC",
  "Minnesota United FC",        "MLS",    "Minnesota United",
  "New England Revolution",     "MLS",    "New England Revolution",
  "New York City FC",           "MLS",    "New York City FC",
  "New York Red Bulls",         "MLS",    "Red Bull New York",
  "Orlando City SC",            "MLS",    "Orlando City",
  "St. Louis City SC",          "MLS",    "St. Louis City",
  "Vancouver Whitecaps FC",     "MLS",    "Vancouver Whitecaps",
  # ── SERA ──────────────────────────────────────────────
  "AC Milan",                   "SERA",   "Milan",
  "Atalanta BC",                "SERA",   "Atalanta",
  "Inter Milan",                "SERA",   "Inter",
  "AS Roma",                    "SERA",   "Roma",
  "Parma Calcio 1913",          "SERA",   "Parma",
  # ── UCL ───────────────────────────────────────────────
  "Atalanta BC",                "UCL",    "Atalanta",
  "Atlético Madrid",            "UCL",    "Atletico Madrid",
  "Paris Saint Germain",        "UCL",    "Paris Saint-Germain",
  "Bayern Munich",              "UCL",    "Bayern München",
  "Borussia Dortmund",          "UCL",    "Borussia Dortmund",
  "Inter Milan",                "UCL",    "Inter",
  "AC Milan",                   "UCL",    "Milan",
  "AS Monaco",                  "UCL",    "Monaco",
  "Qarabağ FK",                 "UCL",    "Qarabag FK",
  "Olympiakos Piraeus",         "UCL",    "Olympiacos",
  # ── UEL ───────────────────────────────────────────────
  "Ferencváros TC",             "UEL",    "Ferencvaros",
  "KRC Genk",                   "UEL",    "Genk",
  "Panathinaikos FC",           "UEL",    "Panathinaikos",
  "Red Star Belgrade",          "UEL",    "FK Crvena Zvezda",
  "PAOK",                       "UEL",    "PAOK Thessaloniki",
  "Fenerbahce",                 "UEL",    "Fenerbahçe",
  "Viktoria Plzeň",             "UEL",    "Viktoria Plzen",
  "SC Freiburg",                "UEL",    "Freiburg",
  "AS Roma",                    "UEL",    "Roma",
  "SK Brann",                   "UEL",    "Brann",
  "Nottingham Forest",          "UEL",    "Nottingham Forest",
  "Celta Vigo",                 "UEL",    "Celta Vigo",
  "Lyon",                       "UEL",    "Lyon",
  "Nice",                       "UEL",    "Nice"
)

SOCCER_ESPN_SLUGS <- tribble(
  ~league_label, ~espn_slug,
  "EPL",         "eng.1",
  "BUND",        "ger.1",
  "SERA",        "ita.1",
  "LIGA",        "esp.1",
  "LIG1",        "fra.1",
  "MLS",         "usa.1",
  "UCL",         "uefa.champions",
  "UEL",         "uefa.europa"
)

SOCCER_ESPN_NAME_MAP <- tribble(
  ~espn_name,                ~league, ~log_name,
  # BUND (examples; expand as mismatches found)
  "Bayern Munich",           "BUND",  "Bayern München",
  "Borussia Monchengladbach","BUND",  "Borussia Mönchengladbach",
  "Heidenheim",              "BUND",  "FC Heidenheim",
  "Mainz",                   "BUND",  "Mainz 05",
  "Freiburg",                "BUND",  "Freiburg",
  "Wolfsburg",               "BUND",  "Wolfsburg",
  "Hoffenheim",              "BUND",  "Hoffenheim",
  "St. Pauli",               "BUND",  "St. Pauli",
  # EPL
  "AFC Bournemouth",         "EPL",   "AFC Bournemouth",
  "Brighton & Hove Albion",  "EPL",   "Brighton & Hove Albion",
  # LIGA
  "Atletico Madrid",         "LIGA",  "Atletico Madrid",
  "Athletic Club",           "LIGA",  "Athletic Club",
  "Alaves",                  "LIGA",  "Deportivo Alaves",
  "Osasuna",                 "LIGA",  "Osasuna",
  # LIG1
  "Paris Saint-Germain",     "LIG1",  "Paris Saint-Germain",
  "Monaco",                  "LIG1",  "Monaco",
  "Lens",                    "LIG1",  "Lens",
  # SERA
  "AC Milan",                "SERA",  "Milan",
  "Atalanta",                "SERA",  "Atalanta",
  "Inter Milan",             "SERA",  "Inter",
  "Roma",                    "SERA",  "Roma",
  "Parma",                   "SERA",  "Parma"
)

normalize_espn_name <- function(espn_name, league) {
  matched <- SOCCER_ESPN_NAME_MAP %>%
    filter(espn_name == !!espn_name, league == !!league) %>%
    pull(log_name)
  if (length(matched) == 1) matched else espn_name
}


normalize_soccer_team <- function(toa_name, league) {
  matched <- SOCCER_NAME_MAP %>%
    filter(toa_name == !!toa_name, league == !!league) %>%
    pull(fotmob_name)
  if (length(matched) == 1) matched else toa_name
}

# 3) Standings fetch + Pythagorean + draw rates
fetch_soccer_standings <- function(fotmob_id, league_label, pyth_exp, ...) {
  cat("Fetching standings:", league_label, "\n")
  
  raw <- tryCatch(
    fotmob_get_league_tables(league_id = fotmob_id) %>%
      filter(table_type == "all"),
    error = function(e) {
      message("ERROR fetching ", league_label, ": ", e$message)
      return(NULL)
    }
  )
  if (is.null(raw) || nrow(raw) == 0) return(NULL)
  
  raw %>%
    mutate(
      team          = table_name,
      games_played  = table_played,
      wins          = table_wins,
      draws         = table_draws,
      losses        = table_losses,
      goals_for     = as.integer(sub("(\\d+)-\\d+",  "\\1", table_scores_str)),
      goals_against = as.integer(sub("\\d+-(\\d+)",  "\\1", table_scores_str)),
      actual_winpct = (wins + 0.5 * draws) / games_played,
      league        = league_label,
      pyth_exp      = pyth_exp,
      pyth_winpct   = goals_for^pyth_exp / (goals_for^pyth_exp + goals_against^pyth_exp)
    ) %>%
    select(league, team, games_played, wins, draws, losses,
           goals_for, goals_against, actual_winpct, pyth_exp, pyth_winpct)
}

soccer_standings_list <- pmap(
  SOCCER_LEAGUES %>% select(fotmob_id, league_label, pyth_exp),
  ~ fetch_soccer_standings(..1, ..2, ..3)
)

soccer_standings_all <- bind_rows(soccer_standings_list) %>%
  group_by(league, team) %>%
  slice(1) %>%          # MLS/UCL/UEL: keep first (overall) table
  ungroup()

soccer_draw_rates <- soccer_standings_all %>%
  group_by(league) %>%
  summarise(
    total_draws  = sum(draws),
    total_played = sum(games_played),
    draw_rate    = total_draws / total_played,
    .groups      = "drop"
  )

cat("\nDynamic draw rates:\n")
print(soccer_draw_rates)

cat("\nStandings rows per league:\n")
print(count(soccer_standings_all, league))

# 4) TOA team list (for future diagnostics or joins)
toa_soccer_teams <- multi_odds_filtered %>%
  filter(grepl("soccer", sport_key)) %>%
  left_join(SOCCER_LEAGUES %>% select(sport_key, league_label),
            by = "sport_key") %>%
  filter(!is.na(league_label)) %>%
  distinct(league = league_label, toa_name = home_team)

# ============================================================
# SOCCER ODDS PIVOT + GAME TABLE
# ============================================================

# 5a) Pivot h2h (1X2) to wide — one row per game × bookmaker
soccer_h2h_wide <- multi_odds_filtered %>%
  filter(grepl("soccer", sport_key), market_key == "h2h") %>%
  left_join(SOCCER_LEAGUES %>% select(sport_key, league_label), by = "sport_key") %>%
  filter(!is.na(league_label)) %>%
  mutate(
    game_date      = as.Date(substr(commence_time, 1, 10)),
    home_team_norm = map2_chr(home_team, league_label, normalize_soccer_team),
    away_team_norm = map2_chr(away_team, league_label, normalize_soccer_team),
    side = case_when(
      outcomes_name == home_team ~ "home_ml",
      outcomes_name == away_team ~ "away_ml",
      TRUE                       ~ "draw_ml"
    )
  ) %>%
  select(game_date, commence_time, league = league_label, home_team_norm, away_team_norm,
         bookmaker_key, side, outcomes_price) %>%
  pivot_wider(names_from = side, values_from = outcomes_price,
              values_fn = first) %>%
  filter(!is.na(home_ml), !is.na(away_ml), !is.na(draw_ml))

cat("\nSoccer h2h wide:", nrow(soccer_h2h_wide), "rows\n")
glimpse(soccer_h2h_wide[1:3, ])

# ============================================================
# SOCCER GAME TABLE — standings + draw rates joined in
# ============================================================

soccer_games <- soccer_h2h_wide %>%
  left_join(
    soccer_standings_all %>%
      select(league, team, pyth_winpct, actual_winpct,
             wins, draws, losses, goals_for, goals_against, games_played),
    by = c("league", "home_team_norm" = "team")
  ) %>%
  rename_with(~ paste0("home_", .),
              c(pyth_winpct, actual_winpct, wins, draws,
                losses, goals_for, goals_against, games_played)) %>%
  left_join(
    soccer_standings_all %>%
      select(league, team, pyth_winpct, actual_winpct,
             wins, draws, losses, goals_for, goals_against, games_played),
    by = c("league", "away_team_norm" = "team")
  ) %>%
  rename_with(~ paste0("away_", .),
              c(pyth_winpct, actual_winpct, wins, draws,
                losses, goals_for, goals_against, games_played)) %>%
  left_join(soccer_draw_rates %>% select(league, draw_rate), by = "league") %>%
  filter(!is.na(home_pyth_winpct), !is.na(away_pyth_winpct)) %>%
  mutate(
    # Head-to-head raw win probs (2-way)
    raw_home_prob   = home_pyth_winpct / (home_pyth_winpct + away_pyth_winpct),
    raw_away_prob   = away_pyth_winpct / (home_pyth_winpct + away_pyth_winpct),
    # Distribute draw rate — sums to 1
    model_home_prob = raw_home_prob * (1 - draw_rate),
    model_draw_prob = draw_rate,
    model_away_prob = raw_away_prob * (1 - draw_rate)
  )

cat("\nsoccer_games:", nrow(soccer_games), "rows,",
    n_distinct(paste(soccer_games$home_team_norm, soccer_games$away_team_norm)),
    "unique matchups\n")
cat("Rows with NA pyth (dropped):",
    sum(is.na(soccer_h2h_wide$home_ml)), "\n")
glimpse(soccer_games[1:3, ])

# ============================================================
# SOCCER VALUE BET ENGINE (1X2 / 3-outcome)
# ============================================================

calc_soccer_value_bets <- function(soccer_games_df) {
  valued <- soccer_games_df %>%
    filter(!is.na(home_ml), !is.na(away_ml), !is.na(draw_ml),
           !is.na(model_home_prob), !is.na(model_away_prob)) %>%
    mutate(
      # No-vig 3-way probabilities
      overround      = 1/home_ml + 1/draw_ml + 1/away_ml,
      home_novigprob = (1/home_ml) / overround,
      draw_novigprob = (1/draw_ml) / overround,
      away_novigprob = (1/away_ml) / overround,
      
      # EV per outcome
      home_ev = model_home_prob * home_ml - 1,
      draw_ev = model_draw_prob * draw_ml - 1,
      away_ev = model_away_prob * away_ml - 1,
      
      # Edge above no-vig line
      home_edge = model_home_prob - home_novigprob,
      draw_edge = model_draw_prob - draw_novigprob,
      away_edge = model_away_prob - away_novigprob,
      
      # Two-gate value flags (5% EV + positive edge + EV cap)
      home_value = home_ev > EV_GATE & home_ev <= EV_CAP & home_edge > 0,
      draw_value = draw_ev > EV_GATE & draw_ev <= EV_CAP & draw_edge > 0,
      away_value = away_ev > EV_GATE & away_ev <= EV_CAP & away_edge > 0,
      
      # Quarter Kelly per side
      home_kelly_q = pmax(((home_ml-1)*model_home_prob - (1-model_home_prob))/(home_ml-1), 0) / 4,
      draw_kelly_q = pmax(((draw_ml-1)*model_draw_prob - (1-model_draw_prob))/(draw_ml-1), 0) / 4,
      away_kelly_q = pmax(((away_ml-1)*model_away_prob - (1-model_away_prob))/(away_ml-1), 0) / 4
    )
  
  bind_rows(
    valued %>% filter(home_value) %>%
      transmute(
        sport = paste0("SOCCER-", league), game_date, open_time = Sys.time(),
        home_team = home_team_norm, away_team = away_team_norm,
        bookmaker_key, value_side = "home_value",
        bet_team = home_team_norm, bet_ml = home_ml,
        home_novigprob, away_novigprob,
        home_pyth = model_home_prob, away_pyth = model_away_prob,
        home_ev, away_ev, home_edge, away_edge,
        home_value, away_value = FALSE,
        bet_ev = home_ev,        # <-- standardized bet EV
        raw_kelly = home_kelly_q,
        # ── Lifecycle fields ──────────────────────────────
        position_id   = make_position_id(sport, game_date,
                                         home_team_norm, away_team_norm,
                                         "home_value", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start    = as.POSIXct(commence_time, tz = "UTC"),
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_real_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      ),
    valued %>% filter(draw_value) %>%
      transmute(
        sport = paste0("SOCCER-", league), game_date, open_time = Sys.time(),
        home_team = home_team_norm, away_team = away_team_norm,
        bookmaker_key, value_side = "draw_value",
        bet_team = "Draw", bet_ml = draw_ml,
        home_novigprob, away_novigprob,
        home_pyth = model_home_prob, away_pyth = model_away_prob,
        home_ev, away_ev, home_edge, away_edge,
        home_value = FALSE, away_value = FALSE,
        bet_ev = draw_ev,        # <-- standardized bet EV
        raw_kelly = home_kelly_q,
        # ── Lifecycle fields ──────────────────────────────
        position_id   = make_position_id(sport, game_date,
                                         home_team_norm, away_team_norm,
                                         "draw_value", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start    = as.POSIXct(commence_time, tz = "UTC"),
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_real_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      ),
    valued %>% filter(away_value) %>%
      transmute(
        sport = paste0("SOCCER-", league), game_date, open_time = Sys.time(),
        home_team = home_team_norm, away_team = away_team_norm,
        bookmaker_key, value_side = "away_value",
        bet_team = away_team_norm, bet_ml = away_ml,
        home_novigprob, away_novigprob,
        home_pyth = model_home_prob, away_pyth = model_away_prob,
        home_ev, away_ev, home_edge, away_edge,
        home_value = FALSE, away_value = TRUE,
        bet_ev = away_ev,        # <-- standardized bet EV
        raw_kelly = home_kelly_q,
        # ── Lifecycle fields ──────────────────────────────
        position_id   = make_position_id(sport, game_date,
                                         home_team_norm, away_team_norm,
                                         "away_value", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start    = as.POSIXct(commence_time, tz = "UTC"),
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_real_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      )
  ) %>%
    arrange(desc(bet_ev))        # <-- sort by the actual bet's EV, not home_ev
  
}

# ---- Run it + best-book dedup ----
value_soccer_raw <- calc_soccer_value_bets(soccer_games)

value_soccer <- value_soccer_raw %>%
  group_by(sport, game_date, home_team, away_team, value_side) %>%
  slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
  ungroup()

cat("\n--- Soccer Value Bets (best book per game/side) ---\n")
cat(nrow(value_soccer), "soccer ML value bets\n\n")
print(value_soccer %>%
        select(sport, game_date, home_team, away_team,
               value_side, bet_team, bet_ml, bet_ev, raw_kelly))

# Confirm all bets have positive bet_ev (should return 0 rows)
value_soccer %>% filter(bet_ev <= 0.05) %>% 
  select(sport, game_date, home_team, away_team, value_side, bet_ev)

# ============================================================
# MLB PIPELINE — Pythagenpat + BaseRuns + Adaptive Blending
# ============================================================

MLB_SPORT_KEY <- "baseball_mlb_preseason"  # Now
# MLB_SPORT_KEY <- "baseball_mlb"          # Flip back March 27
MLB_SEASON    <- 2025  # ← UPDATE TO 2026 WHEN SEASON STARTS (~March 27)
HFA_MLB       <- 0.025  # ~2.5% home field advantage

# BACKTEST HYPERPARAMETERS — tune these during back-testing
# Research suggests g1=40 g2=100 but verify with your data
MLB_BSR_G1    <- 40     # Games below this: max BaseRuns weight
MLB_BSR_G2    <- 100    # Games above this: max Pythagenpat weight
MLB_BSR_WMAX  <- 0.70   # BaseRuns weight early season
MLB_BSR_WMIN  <- 0.30   # BaseRuns weight late season

# Park factors (all 30 teams — neutral = 1.00)
# BACKTEST NOTE: Pull full park factor table from BRef before season
MLB_PARK_FACTORS <- tribble(
  ~team_name,                    ~park_factor,
  "Colorado Rockies",             1.28,
  "Boston Red Sox",               1.06,
  "Philadelphia Phillies",        1.07,
  "Cincinnati Reds",              1.05,
  "Chicago Cubs",                 1.04,
  "Texas Rangers",                1.03,
  "New York Yankees",             1.02,
  "Toronto Blue Jays",            1.01,
  "Atlanta Braves",               1.01,
  "Houston Astros",               1.00,
  "Kansas City Royals",           1.00,
  "Milwaukee Brewers",            1.00,
  "New York Mets",                1.00,
  "St. Louis Cardinals",          0.99,
  "Detroit Tigers",               0.99,
  "Washington Nationals",         0.99,
  "Baltimore Orioles",            0.99,
  "Minnesota Twins",              0.98,
  "Miami Marlins",                0.98,
  "Tampa Bay Rays",               0.98,
  "Pittsburgh Pirates",           0.98,
  "Cleveland Guardians",          0.97,
  "Los Angeles Dodgers",          0.97,
  "Arizona Diamondbacks",         0.97,
  "Los Angeles Angels",           0.97,
  "Chicago White Sox",            0.97,
  "San Diego Padres",             0.96,
  "Athletics",                    0.96,
  "San Francisco Giants",         0.95,
  "Seattle Mariners",             0.94
)

fetch_mlb_standings <- function(season = MLB_SEASON) {
  
  bat <- mlb_teams_stats(season = season, stat_type = "season", stat_group = "hitting") %>%
    select(
      team_name    = team_name,
      team_id      = team_id,
      games_played = games_played,
      RS           = runs,
      H            = hits,
      HR           = home_runs,
      BB           = base_on_balls,
      TB           = total_bases,
      AB           = at_bats
    ) %>%
    mutate(across(c(games_played, RS, H, HR, BB, TB, AB), as.numeric))
  
  pit <- mlb_teams_stats(season = season, stat_type = "season", stat_group = "pitching") %>%
    select(
      team_name = team_name,
      W         = wins,
      L         = losses,
      RA        = runs,
      fip       = fip        # verify: names(mlb_teams_stats(..., stat_group="pitching"))
    ) %>%
    mutate(across(c(W, L, RA, fip), as.numeric))
  
  inner_join(bat, pit, by = "team_name") %>%
    left_join(MLB_PARK_FACTORS, by = "team_name") %>%
    mutate(
      park_factor   = coalesce(park_factor, 1.00),
      actual_winpct = W / (W + L),
      APF           = RS / games_played,
      APA           = RA / games_played,
      rpg           = (RS + RA) / games_played,
      
      # Dynamic Pythagorean (Pythagenpat) — exponent confirmed from your 2025 sheet
      pyth_exp      = rpg ^ 0.287,
      pyth_winpct   = RS^pyth_exp / (RS^pyth_exp + RA^pyth_exp),
      
      # BaseRuns — NOTE: BsR_B uses the standard Smyth formula; if your sheet uses
      # additional terms (HBP, SB, CS, SF), update the BsR_B line to match.
      BsR_A         = H + BB - HR,
      BsR_B         = 1.4 * TB - 0.6 * H - 3 * HR + 0.1 * BB,
      BsR_C         = AB - H,
      BsR_D         = HR,
      BsR_raw       = pmax(BsR_A * BsR_B / (BsR_B + BsR_C) + BsR_D, 0.1),
      
      # BsRA via FIP (confirmed: FIP * G from your sheet)
      BsRA          = fip * games_played,
      bsr_rpg       = (BsR_raw + BsRA) / games_played,
      
      # BaseRuns Pythagorean (exponent confirmed from your 2025 sheet)
      bsr_exp       = bsr_rpg ^ 0.285,
      baseruns_winpct = BsR_raw^bsr_exp / (BsR_raw^bsr_exp + BsRA^bsr_exp),
      
      # Adaptive blend: BaseRuns-heavy early, Pythagorean-heavy late
      bsr_weight    = case_when(
        games_played < MLB_BSR_G1 ~ MLB_BSR_WMAX,
        games_played > MLB_BSR_G2 ~ MLB_BSR_WMIN,
        TRUE ~ MLB_BSR_WMAX - (MLB_BSR_WMAX - MLB_BSR_WMIN) *
          (games_played - MLB_BSR_G1) / (MLB_BSR_G2 - MLB_BSR_G1)
      ),
      blended_winpct = bsr_weight * baseruns_winpct + (1 - bsr_weight) * pyth_winpct
    )
}


# Try live data first, fall back to your spreadsheet
mlb_standings_df <- tryCatch({
  df <- fetch_mlb_standings(season = 2025)
  if (nrow(df) >= 25) {
    cat("✅ Live MLB standings loaded:", nrow(df), "teams\n")
    df
  } else {
    stop("Insufficient teams returned")
  }
}, error = function(e) {
  cat("⚠️  Live standings unavailable — loading 2025 spreadsheet\n")
  read_excel(file.path(SUREBET_DIR, "2025MLBRef.xlsx"), sheet = "MLB Odds") %>%
    transmute(
      team_name     = Team,
      team_id       = NA_integer_,
      games_played  = as.integer(Gms),
      wins          = as.integer(W),
      losses        = as.integer(L),
      RS            = as.numeric(RS),
      RA            = as.numeric(RA),
      H             = as.numeric(H),
      HR            = as.numeric(HR),
      BB             = as.numeric(BB),
      TB             = as.numeric(TB),
      AB             = as.numeric(AB),
      HBP           = NA_real_,
      SF            = NA_real_,
      SH            = NA_real_,
      CS            = NA_real_,
      GIDP          = NA_real_,
      park_factor   = 1.00,
      actual_winpct = wins / games_played,
      APF           = as.numeric(APF),
      APA           = as.numeric(APA),
      rpg           = (RS + RA) / games_played,
      pyth_exp      = rpg^0.287,
      pyth_winpct   = RS^pyth_exp / (RS^pyth_exp + RA^pyth_exp),
      BsR_A         = H + BB - HR,
      BsR_B         = 1.4 * TB - 0.6 * H - 3 * HR + 0.1 * BB,
      BsR_C         = AB - H,
      BsR_D         = HR,
      BsR_raw       = pmax(BsR_A * BsR_B / (BsR_B + BsR_C) + BsR_D, 0.1),
      baseruns_winpct = BsR_raw / (BsR_raw + RA),
      bsr_weight    = MLB_BSR_WMIN,  # Late season data → Pyth weighted
      blended_winpct = bsr_weight * baseruns_winpct + (1 - bsr_weight) * pyth_winpct
    ) %>%
    left_join(MLB_PARK_FACTORS, by = "team_name") %>%
    mutate(park_factor = coalesce(park_factor.y, park_factor.x, 1.00)) %>%
    select(-starts_with("park_factor."))
})

cat("✅ MLB standings ready:", nrow(mlb_standings_df), "teams\n")
print(mlb_standings_df %>%
        select(team_name, games_played, pyth_winpct,
               baseruns_winpct, bsr_weight, blended_winpct) %>%
        arrange(desc(blended_winpct)))

multi_odds_filtered %>%
  filter(grepl("baseball", sport_key)) %>%
  distinct(sport_key)

# ── Supplemental MLB odds fetch (key changes ~March 27) ──────────────────────
odds_mlb_supp <- tryCatch({
  suppressWarnings(
    toa_sports_odds(sport_key = MLB_SPORT_KEY,
                    regions   = "us,us2",
                    markets   = "h2h,totals") %>%
      mutate(sport_key = MLB_SPORT_KEY)
  ) %>% filter(bookmaker_key %in% books)
}, error = function(e) {
  message("⚠️  MLB odds fetch failed (", MLB_SPORT_KEY, "): ", e$message)
  tibble()   # return empty tibble — downstream code handles 0-row gracefully
})

cat("MLB odds fetched:", nrow(odds_mlb_supp), "rows\n")

if (!MLB_SPORT_KEY %in% multi_odds_filtered$sport_key) {
  multi_odds_filtered <- bind_rows(multi_odds_filtered, odds_mlb_supp)
  cat("MLB odds appended:", nrow(odds_mlb_supp), "rows\n")
} else {
  cat("MLB odds already present — skipping append\n")
}
cat("MLB odds appended:", nrow(odds_mlb_supp), "rows\n")

# ── 2) Spring Training odds (baseball_mlb_preseason)
odds_mlb <- multi_odds_filtered %>%
  filter(sport_key == MLB_SPORT_KEY) %>%
  distinct(game_date = as.Date(substr(commence_time, 1, 10)),
           home_team, away_team, bookmaker_key,
           market_key, outcomes_name, .keep_all = TRUE) %>%
  mutate(game_date = as.Date(substr(commence_time, 1, 10)))


cat("MLB odds found:", nrow(odds_mlb), "\n")
print(odds_mlb %>% distinct(home_team, away_team) %>% head(5))

# ── MLB crosswalk diagnostic (run once; add mismatches to name_crosswalk) ────
mlb_toa_teams <- bind_rows(
  odds_mlb %>% distinct(team_name = home_team),
  odds_mlb %>% distinct(team_name = away_team)
) %>% distinct()

mlb_standings_teams <- mlb_standings_df %>% distinct(team_name)

mlb_unmatched_toa  <- anti_join(mlb_toa_teams, mlb_standings_teams, by = "team_name")
mlb_unmatched_stat <- anti_join(mlb_standings_teams, mlb_toa_teams,   by = "team_name")

cat("\n── MLB name mismatches ───────────────────────────────────────────\n")
cat("TOA names with no standings match (add to name_crosswalk → standard_name):\n")
print(mlb_unmatched_toa)
cat("Standings names with no TOA match (confirm spelling):\n")
print(mlb_unmatched_stat)
cat("─────────────────────────────────────────────────────────────────\n")


# ── 3) Build mlb_games with your blended model + HFA + park
h2h_mlb <- odds_mlb %>%
  filter(market_key == "h2h") %>%
  mutate(side = if_else(outcomes_name == home_team, "home_ml", "away_ml")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price) %>%
  pivot_wider(names_from = side, values_from = outcomes_price, values_fn = first) %>%
  mutate(across(c(home_ml, away_ml), as.numeric))

totals_mlb_wide <- odds_mlb %>%
  filter(market_key == "totals") %>%
  mutate(side = if_else(outcomes_name == "Over", "over", "under")) %>%
  select(game_date, home_team, away_team, bookmaker_key, side, outcomes_price, outcomes_point) %>%
  pivot_wider(names_from = side,
              values_from = c(outcomes_price, outcomes_point),
              names_glue = "{side}_{.value}",
              values_fn = first) %>%
  mutate(across(starts_with("over_") | starts_with("under_"), as.numeric))

mlb_games <- h2h_mlb %>%
  left_join(totals_mlb_wide, by = c("game_date", "home_team", "away_team", "bookmaker_key")) %>%
  left_join(mlb_standings_df %>% select(team_name, blended_winpct, APF, APA, park_factor),
            by = c("home_team" = "team_name")) %>%
  rename(home_blended = blended_winpct, home_apf = APF, home_apa = APA, home_park = park_factor) %>%
  left_join(mlb_standings_df %>% select(team_name, blended_winpct, APF, APA),
            by = c("away_team" = "team_name")) %>%
  rename(away_blended = blended_winpct, away_apf = APF, away_apa = APA) %>%
  mutate(
    home_adj       = home_blended * (1 + HFA_MLB),
    away_adj       = away_blended * (1 - HFA_MLB),
    home_h2h_prob  = home_adj / (home_adj + away_adj), away_h2h_prob  = 1 - home_h2h_prob,
    expected_total = (home_apf + away_apa + away_apf + home_apa) / 2
  ) %>%
  filter(!is.na(home_blended), !is.na(away_blended))


cat("✅ MLB games enriched:", nrow(mlb_games), "\n")
glimpse(mlb_games[1:3, c("home_team", "away_team", "home_h2h_prob", "expected_total")])

# ADD THIS — preseason block has no commence_time; filled on March 27
mlb_games <- mlb_games %>% mutate(game_start = as.POSIXct(NA_character_))

calc_mlb_totals <- function(games_df, sport_label = "MLB",
                            sigma = MLB_SIGMA, ev_gate = EV_GATE) {
  out <- games_df %>%
    filter(!is.na(over_outcomes_point),
           !is.na(over_outcomes_price),
           !is.na(under_outcomes_price),
           !is.na(expected_total)) %>%
    mutate(
      total_line       = as.numeric(over_outcomes_point),
      over_price       = as.numeric(over_outcomes_price),
      under_price      = as.numeric(under_outcomes_price),
      # Normal CDF: sigma ≈ 2.5 runs is typical MLB game-total SD
      model_over_prob  = pnorm((expected_total - total_line) / sigma),
      model_under_prob = 1 - model_over_prob,
      overround        = 1/over_price + 1/under_price,
      over_novigprob   = (1/over_price)  / overround,
      under_novigprob  = (1/under_price) / overround,
      over_ev          = model_over_prob  * over_price  - 1,
      under_ev         = model_under_prob * under_price - 1,
      over_edge        = model_over_prob  - over_novigprob,
      under_edge       = model_under_prob - under_novigprob,
      over_kelly_q     = pmax((over_price  - 1) * model_over_prob  - (1 - model_over_prob),  0) /
        (4 * (over_price  - 1)),
      under_kelly_q    = pmax((under_price - 1) * model_under_prob - (1 - model_under_prob), 0) /
        (4 * (under_price - 1))
    )
  
  bind_rows(
    out %>%
      filter(over_ev > ev_gate, over_ev <= EV_CAP, over_edge > 0) %>%
      transmute(sport = sport_label, game_date, open_time = Sys.time(),
                home_team, away_team, bookmaker_key,
                bet_type = "OVER",  bet_team = paste("Over",  total_line),
                bet_ml = over_price,  bet_line = total_line,
                raw_kelly = over_kelly_q,
                bet_ev    = over_ev,
                # ── Lifecycle fields ──────────────────────────────
                position_id   = make_position_id(sport_label, game_date,
                                                 home_team, away_team, "OVER", bookmaker_key),
                status        = "IDENTIFIED",
                placed_time   = as.POSIXct(NA),
                game_start    = as.POSIXct(NA),
                settle_time   = as.POSIXct(NA),
                stake         = NA_real_,
                result        = NA_character_,
                cashout_value = NA_real_,
                hedge_time    = as.POSIXct(NA),
                hedge_book    = NA_character_,
                hedge_ml      = NA_real_,
                hedge_stake   = NA_real_,
                hedge_result  = NA_real_,
                clv_at_action = NA_real_,
                pnl           = NA_real_
      ),
    out %>%
      filter(under_ev > ev_gate, under_ev <= EV_CAP, under_edge > 0) %>%
      transmute(sport = sport_label, game_date, open_time = Sys.time(),
                home_team, away_team, bookmaker_key,
                bet_type = "UNDER", bet_team = paste("Under", total_line),
                bet_ml = under_price, bet_line = total_line,
                raw_kelly = under_kelly_q,
                bet_ev    = under_ev,
                # ── Lifecycle fields ──────────────────────────────
                position_id   = make_position_id(sport_label, game_date,
                                                 home_team, away_team, "UNDER", bookmaker_key),
                status        = "IDENTIFIED",
                placed_time   = as.POSIXct(NA),
                game_start    = as.POSIXct(NA),
                settle_time   = as.POSIXct(NA),
                stake         = NA_real_,
                result        = NA_character_,
                cashout_value = NA_real_,
                hedge_time    = as.POSIXct(NA),
                hedge_book    = NA_character_,
                hedge_ml      = NA_real_,
                hedge_stake   = NA_real_,
                hedge_result  = NA_real_,
                clv_at_action = NA_real_,
                pnl           = NA_real_
      )
  ) %>% arrange(desc(bet_ev))
}

# ── 4) Value bets (h2h + totals) ─────────────────────────────────────────────
# AFTER
value_mlb <- calc_value_bets(mlb_games, home_h2h_prob, away_h2h_prob, "MLB") %>%
  filter(home_value | away_value) %>%
  mutate(
    value_side = case_when(
      home_value & away_value ~ "both",
      home_value              ~ "home",
      away_value              ~ "away",
      TRUE                    ~ NA_character_
    ),
    raw_kelly = case_when(
      value_side == "home" ~ home_kelly_q,
      value_side == "away" ~ away_kelly_q,
      value_side == "both" ~ pmax(home_kelly_q, away_kelly_q),
      TRUE                 ~ 0
    ),
    bet_team = case_when(
      value_side == "home" ~ home_team,
      value_side == "away" ~ away_team,
      value_side == "both" ~ paste(home_team, "+", away_team),
      TRUE                 ~ NA_character_
    ),
    bet_ml   = case_when(
      value_side == "home" ~ home_ml,
      value_side == "away" ~ away_ml,
      TRUE                 ~ NA_real_
    ),
    bet_ev   = case_when(
      value_side == "home" ~ home_ev,
      value_side == "away" ~ away_ev,
      TRUE                 ~ NA_real_
    ),
    implied_prob  = 1 / bet_ml,
    open_time     = Sys.time(),
    position_id   = make_position_id(sport, game_date, home_team,
                                     away_team, value_side, bookmaker_key),
    status        = "IDENTIFIED",
    placed_time   = as.POSIXct(NA),
    game_start    = as.POSIXct(NA),   # MLB odds lack commence_time in preseason block
    settle_time   = as.POSIXct(NA),
    stake         = NA_real_,
    result        = NA_character_,
    cashout_value = NA_real_,
    hedge_time    = as.POSIXct(NA),
    hedge_book    = NA_character_,
    hedge_ml      = NA_real_,
    hedge_stake   = NA_real_,
    hedge_result  = NA_real_,
    clv_at_action = NA_real_,
    pnl           = NA_real_
  ) %>%
  group_by(game_date, home_team, away_team, value_side) %>%
  slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
  ungroup()


totals_mlb <- calc_mlb_totals(mlb_games) %>%
  group_by(game_date, home_team, away_team, bet_type) %>%
  slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
  ungroup()

cat(sprintf("✅ MLB value bets — ML: %d | Totals: %d\n", nrow(value_mlb), nrow(totals_mlb)))

# ── PARKING LOT ───────────────────────────────────────────────────────────────
# # TODO (March 27): Wire MLB into settle_paper_day
# Add mlb_pnl_by_date argument (same pattern as soccer_pnl_by_date_arg)
# Compute mlb_day_pnl_kelly from mlb_settled_today grouped by game_date
# Add to settled_pnl_kelly, settled_pnl_dollar, ending_bankroll, wins, losses
# ─────────────────────────────────────────────────────────────────────────────

# ── 5) Logging

# ── Dynamic LEAGUE_AVG overrides (place BEFORE enrichment mutations) ──────────
LEAGUE_AVG_NBA <- mean(
  c(nba_standings$PointsPG, nba_standings$OppPointsPG), na.rm = TRUE
)
LEAGUE_AVG_NCAAB <- ncaab_standings %>%
  summarise(avg = sum(ptsFor + ptsAgainst) / sum(gamesPlayed * 2)) %>%
  pull(avg)
LEAGUE_AVG_NHL <- nhl_standings %>%
  summarise(avg = sum(goalFor + goalAgainst) / sum(gamesPlayed * 2)) %>%
  pull(avg)

cat(sprintf("Live league avgs — NBA: %.1f | NCAAB: %.1f | NHL: %.2f\n",
            LEAGUE_AVG_NBA, LEAGUE_AVG_NCAAB, LEAGUE_AVG_NHL))

# ── NBA ───────────────────────────────────────────────────────────────────────
nba_games <- nba_games %>%
  left_join(
    nba_standings %>% select(team, apf, apa, pace, off_rating, def_rating),
    by = c("home_team" = "team")
  ) %>%
  rename(home_apf = apf, home_apa = apa,
         home_pace = pace, home_off_rating = off_rating,
         home_def_rating = def_rating) %>%
  left_join(
    nba_standings %>% select(team, apf, apa, pace, off_rating, def_rating),
    by = c("away_team" = "team")
  ) %>%
  rename(away_apf = apf, away_apa = apa,
         away_pace = pace, away_off_rating = off_rating,
         away_def_rating = def_rating) %>%
  mutate(
    # Head-to-head normalized probability (fixed vs. original patch)
    home_h2h_prob   = home_pyth_exp_143 / (home_pyth_exp_143 + away_pyth_exp_143),
    expected_spread = calc_expected_spread(home_h2h_prob, k = K_SPREAD_NBA),
    expected_total  = calc_expected_total(
      apf1  = home_apf, apa1  = home_apa,
      apf2  = away_apf, apa2  = away_apa,
      or1   = home_off_rating, dr1 = home_def_rating,
      or2   = away_off_rating, dr2 = away_def_rating,
      pace1 = home_pace,       pace2 = away_pace,
      league_avg = LEAGUE_AVG_NBA
    )
  )

# ── NCAAB ─────────────────────────────────────────────────────────────────────
ncaab_games <- ncaab_games %>%
  left_join(
    ncaab_standings %>%
      mutate(apf = ptsFor / gamesPlayed, apa = ptsAgainst / gamesPlayed) %>%
      select(team_display_name, apf, apa),
    by = c("home_team" = "team_display_name")
  ) %>%
  rename(home_apf = apf, home_apa = apa) %>%
  left_join(
    ncaab_standings %>%
      mutate(apf = ptsFor / gamesPlayed, apa = ptsAgainst / gamesPlayed) %>%
      select(team_display_name, apf, apa),
    by = c("away_team" = "team_display_name")
  ) %>%
  rename(away_apf = apf, away_apa = apa) %>%
  mutate(
    home_h2h_prob   = home_pyth_winpct / (home_pyth_winpct + away_pyth_winpct),
    expected_spread = calc_expected_spread(home_h2h_prob, k = K_SPREAD_NCAAB),
    expected_total  = calc_expected_total(
      apf1 = home_apf, apa1 = home_apa,
      apf2 = away_apf, apa2 = away_apa,
      league_avg = LEAGUE_AVG_NCAAB
    )
  )

# ── NHL ───────────────────────────────────────────────────────────────────────
nhl_games <- nhl_games %>%
  left_join(
    nhl_standings %>%
      mutate(gpf = goalFor / gamesPlayed, gpa = goalAgainst / gamesPlayed) %>%
      select(team, gpf, gpa),
    by = c("home_team" = "team")
  ) %>%
  rename(home_gpf = gpf, home_gpa = gpa) %>%
  left_join(
    nhl_standings %>%
      mutate(gpf = goalFor / gamesPlayed, gpa = goalAgainst / gamesPlayed) %>%
      select(team, gpf, gpa),
    by = c("away_team" = "team")
  ) %>%
  rename(away_gpf = gpf, away_gpa = gpa) %>%
  mutate(
    home_h2h_prob   = home_pyth_exp_dyn / (home_pyth_exp_dyn + away_pyth_exp_dyn),
    expected_spread = calc_expected_spread(home_h2h_prob, k = K_SPREAD_NHL),
    expected_total  = calc_expected_total(
      apf1 = home_gpf, apa1 = home_gpa,
      apf2 = away_gpf, apa2 = away_gpa,
      league_avg = LEAGUE_AVG_NHL
    )
  )

cat("Enrichment complete:\n")
cat(sprintf("  NBA   — expected_spread range: [%.2f, %.2f]\n",
            min(nba_games$expected_spread,   na.rm=TRUE),
            max(nba_games$expected_spread,   na.rm=TRUE)))
cat(sprintf("  NCAAB — expected_spread range: [%.2f, %.2f]\n",
            min(ncaab_games$expected_spread, na.rm=TRUE),
            max(ncaab_games$expected_spread, na.rm=TRUE)))
cat(sprintf("  NHL   — expected_spread range: [%.2f, %.2f]\n",
            min(nhl_games$expected_spread,   na.rm=TRUE),
            max(nhl_games$expected_spread,   na.rm=TRUE)))


# ============================================================
# UNIFIED VALUE BET TABLE — NBA + NCAAB + NHL
# ============================================================

# League average scoring for two-method totals model
# ── After nba_standings is built ─────────────────────────────────────────────
LEAGUE_AVG_NBA <- mean(
  c(nba_standings$PointsPG, nba_standings$OppPointsPG),
  na.rm = TRUE
)
cat(sprintf("NBA league avg scoring: %.1f pts/team/game\n", LEAGUE_AVG_NBA))

# ── After ncaab_standings is built ───────────────────────────────────────────
LEAGUE_AVG_NCAAB <- ncaab_standings %>%
  summarise(avg = sum(ptsFor + ptsAgainst) / sum(gamesPlayed * 2)) %>%
  pull(avg)
cat(sprintf("NCAAB league avg scoring: %.1f pts/team/game\n", LEAGUE_AVG_NCAAB))

# ── After nhl_standings is built ─────────────────────────────────────────────
LEAGUE_AVG_NHL <- nhl_standings %>%
  summarise(avg = sum(goalFor + goalAgainst) / sum(gamesPlayed * 2)) %>%
  pull(avg)
cat(sprintf("NHL league avg scoring: %.2f goals/team/game\n", LEAGUE_AVG_NHL))

#' Expected spread via log-odds.
#' win_prob should be the HEAD-TO-HEAD normalized probability:
#'   home_pyth / (home_pyth + away_pyth)
#' Positive result = home team is model favorite.
calc_expected_spread <- function(win_prob, k = 7.0) {
  win_prob <- pmax(0.01, pmin(0.99, win_prob))
  log(win_prob / (1 - win_prob)) * k
}

#' Expected total — two-method average.
#' Falls back to Method 1 (points-based) when pace/rating data unavailable.
calc_expected_total <- function(apf1, apa1, apf2, apa2,
                                or1 = NULL, dr1 = NULL,
                                or2 = NULL, dr2 = NULL,
                                pace1 = NULL, pace2 = NULL,
                                league_avg = 112.5) {
  etot1 <- ((apf1 + apa1) * (apf2 + apa2)) / (league_avg * 2)
  
  if (!is.null(or1) && !is.null(dr1) && !is.null(or2) && !is.null(dr2) &&
      !is.null(pace1) && !is.null(pace2)) {
    avg_pace <- (pace1 + pace2) / 2
    etot2    <- (((or1 + dr2) / 100 * avg_pace) +
                   ((or2 + dr1) / 100 * avg_pace)) / 2
    return((etot1 + etot2) / 2)
  }
  etot1
}

# ---- Helper: calculate value metrics for one sport ----
calc_value_bets <- function(games_df, pyth_home_col, pyth_away_col, sport_label) {
  
  # Capture column names as quosures — must be first
  pyth_home_col <- enquo(pyth_home_col)
  pyth_away_col <- enquo(pyth_away_col)
  
  games_df %>%
    filter(!is.na(home_ml), !is.na(away_ml)) %>%
    mutate(
      sport          = sport_label,
      # Step 1: No-vig implied probabilities
      overround      = 1/home_ml + 1/away_ml,
      home_novigprob = (1/home_ml) / overround,
      away_novigprob = (1/away_ml) / overround,
      # Step 2: EV
      home_ev        = !!pyth_home_col * home_ml - 1,
      away_ev        = !!pyth_away_col * away_ml - 1,
      # Step 3: Edge above no-vig line
      home_edge      = !!pyth_home_col - home_novigprob,
      away_edge      = !!pyth_away_col - away_novigprob,
      # Step 4: Two-gate value flags
      home_value     = home_ev > EV_GATE & home_ev <= EV_CAP & home_edge > 0,
      away_value     = away_ev > EV_GATE & away_ev <= EV_CAP & away_edge > 0,
      # Step 5: Full Kelly → Quarter Kelly
      home_kelly_full = pmax((home_ml - 1) * !!pyth_home_col - (1 - !!pyth_home_col),
                             0) / (home_ml - 1),
      away_kelly_full = pmax((away_ml - 1) * !!pyth_away_col - (1 - !!pyth_away_col),
                             0) / (away_ml - 1),
      home_kelly_q   = home_kelly_full / 4,
      away_kelly_q   = away_kelly_full / 4
    ) %>%
    select(
      sport, game_date, game_start, home_team, away_team, bookmaker_key,
      home_ml, away_ml,
      home_novigprob, away_novigprob,
      !!quo_name(pyth_home_col) := !!pyth_home_col,
      !!quo_name(pyth_away_col) := !!pyth_away_col,
      home_ev, away_ev, home_edge, away_edge,
      home_value, away_value,
      home_kelly_q, away_kelly_q
    )
}


#' Flag spread and total value bets for one sport
#'
#' Edge-to-probability conversions (rough priors — calibrate after data collection):
#'   Spread : each 1 pt of model edge ≈ 3% win-probability gain  (0.03/pt)
#'   Totals : each 1 pt of model edge ≈ 1.5% cover-probability gain (0.015/pt)
#'
#' Quarter Kelly applied consistently with calc_value_bets().
#'
#' @param games_df    Enriched games df (must contain expected_spread, expected_total,
#'                    *_spread_outcomes_point/price, over/under_outcomes_point/price)
#' @param sport_label "NBA" | "NCAAB" | "NHL"
#' @return            Tidy tibble, one row per flagged bet side

calc_spread_total_bets <- function(games_df, sport_label,
                                   min_spread_edge = MIN_SPREAD_EDGE_PTS,
                                   min_total_edge  = MIN_TOTAL_EDGE_PTS) {
  
  # Defensive check — gives a clear message instead of a cryptic filter() error
  required_cols <- c("expected_spread", "expected_total",
                     "home_spread_outcomes_point", "over_outcomes_point")
  missing_cols  <- setdiff(required_cols, names(games_df))
  if (length(missing_cols) > 0) {
    warning(sport_label, ": missing columns [",
            paste(missing_cols, collapse = ", "),
            "] — check enrichment block placement. Returning empty tibble.")
    return(tibble())
  }
  
  games_clean <- games_df %>%
    filter(!is.na(expected_spread), !is.na(expected_total),
           !is.na(home_spread_outcomes_point),
           !is.na(over_outcomes_point))
  
  if (nrow(games_clean) == 0) {
    message(sport_label, ": no games with complete spread/total data")
    return(tibble())
  }
  
  kelly_q <- function(odds, win_prob) {
    b          <- odds - 1
    kelly_full <- pmax((b * win_prob - (1 - win_prob)) / b, 0)
    kelly_full / 4
  }
  
  bets <- games_clean %>%
    mutate(
      # ── Spread edges ──────────────────────────────────────────────────────
      home_spread_edge_pts =  expected_spread - home_spread_outcomes_point,
      away_spread_edge_pts = -expected_spread - away_spread_outcomes_point,
      
      # ── Total edge (positive → Over, negative → Under) ────────────────────
      total_edge_pts = expected_total - over_outcomes_point,
      
      # ── Edge → win-probability adjustments ────────────────────────────────
      home_spread_win_prob = pmin((1 / home_spread_outcomes_price) +
                                    pmax(home_spread_edge_pts, 0) * 0.03, 0.99),
      away_spread_win_prob = pmin((1 / away_spread_outcomes_price) +
                                    pmax(away_spread_edge_pts, 0) * 0.03, 0.99),
      over_win_prob        = pmin((1 / over_outcomes_price)  +
                                    pmax( total_edge_pts, 0) * 0.015, 0.99),
      under_win_prob       = pmin((1 / under_outcomes_price) +
                                    pmax(-total_edge_pts, 0) * 0.015, 0.99),
      
      # ── Kelly (quarter) ───────────────────────────────────────────────────
      home_spread_kelly_q = kelly_q(home_spread_outcomes_price, home_spread_win_prob),
      away_spread_kelly_q = kelly_q(away_spread_outcomes_price, away_spread_win_prob),
      over_kelly_q        = kelly_q(over_outcomes_price,        over_win_prob),
      under_kelly_q       = kelly_q(under_outcomes_price,       under_win_prob)
    )
  
  # Pivot to one row per flagged bet
  bind_rows(
    
    # Home spread
    bets %>%
      filter(home_spread_edge_pts > min_spread_edge) %>%
      transmute(
        sport         = sport_label,
        game_date, open_time = Sys.time(),
        home_team, away_team, bookmaker_key,
        bet_type      = "SPREAD",
        bet_team      = home_team,
        bet_line      = home_spread_outcomes_point,
        bet_odds      = home_spread_outcomes_price,
        implied_prob  = 1 / home_spread_outcomes_price,
        expected_value = expected_spread,
        bet_edge_pts  = home_spread_edge_pts,
        bet_edge      = home_spread_edge_pts * 0.03,
        raw_kelly     = home_spread_kelly_q,
        position_id   = make_position_id(sport_label, game_date,
                                         home_team, away_team, "SPREAD_HOME", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start = game_start,    # POSIXct — inherited from odds_*_wide join
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_character_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      ),
    
    # Away spread
    bets %>%
      filter(away_spread_edge_pts > min_spread_edge) %>%
      transmute(
        sport         = sport_label,
        game_date, open_time = Sys.time(),
        home_team, away_team, bookmaker_key,
        bet_type      = "SPREAD",
        bet_team      = away_team,
        bet_line      = away_spread_outcomes_point,
        bet_odds      = away_spread_outcomes_price,
        implied_prob  = 1 / away_spread_outcomes_price,
        expected_value = -expected_spread,
        bet_edge_pts  = away_spread_edge_pts,
        bet_edge      = away_spread_edge_pts * 0.03,
        raw_kelly     = away_spread_kelly_q,
        position_id   = make_position_id(sport_label, game_date,
                                         home_team, away_team, "SPREAD_AWAY", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start = game_start,    # POSIXct — inherited from odds_*_wide join
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_character_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      ),
    
    # Over
    bets %>%
      filter(total_edge_pts > min_total_edge) %>%
      transmute(
        sport         = sport_label,
        game_date, open_time = Sys.time(),
        home_team, away_team, bookmaker_key,
        bet_type      = "OVER",
        bet_team      = NA_character_,
        bet_line      = over_outcomes_point,
        bet_odds      = over_outcomes_price,
        implied_prob  = 1 / over_outcomes_price,
        expected_value = expected_total,
        bet_edge_pts  = total_edge_pts,
        bet_edge      = total_edge_pts * 0.015,
        raw_kelly     = over_kelly_q,
        position_id   = make_position_id(sport_label, game_date,
                                         home_team, away_team, "OVER", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start = game_start,    # POSIXct — inherited from odds_*_wide join
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_character_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      ),
    
    # Under
    bets %>%
      filter(total_edge_pts < -min_total_edge) %>%
      transmute(
        sport         = sport_label,
        game_date, open_time = Sys.time(),
        home_team, away_team, bookmaker_key,
        bet_type      = "UNDER",
        bet_team      = NA_character_,
        bet_line      = over_outcomes_point,   # line is always stored on the Over row
        bet_odds      = under_outcomes_price,
        implied_prob  = 1 / under_outcomes_price,
        expected_value = expected_total,
        bet_edge_pts  = abs(total_edge_pts),
        bet_edge      = abs(total_edge_pts) * 0.015,
        raw_kelly     = under_kelly_q,
        position_id   = make_position_id(sport_label, game_date,
                                         home_team, away_team, "UNDER", bookmaker_key),
        status        = "IDENTIFIED",
        placed_time   = as.POSIXct(NA),
        game_start = game_start,    # POSIXct — inherited from odds_*_wide join
        settle_time   = as.POSIXct(NA),
        stake         = NA_real_,
        result        = NA_character_,
        cashout_value = NA_real_,
        hedge_time    = as.POSIXct(NA),
        hedge_book    = NA_character_,
        hedge_ml      = NA_real_,
        hedge_stake   = NA_real_,
        hedge_result  = NA_real_,
        clv_at_action = NA_real_,
        pnl           = NA_real_
      )
    
  ) %>%
    arrange(desc(bet_edge))
}

# ---- Defensive sport validation ----
# Ensure no NBA teams appear in NCAAB games table and vice versa
nba_team_names  <- unique(c(nba_games$home_team,  nba_games$away_team))
ncaab_team_names <- unique(c(ncaab_games$home_team, ncaab_games$away_team))

# Any NBA teams that leaked into NCAAB?
nba_in_ncaab <- intersect(nba_team_names, ncaab_team_names)
if (length(nba_in_ncaab) > 0) {
  message("WARNING: NBA teams found in ncaab_games — removing: ",
          paste(nba_in_ncaab, collapse = ", "))
  ncaab_games <- ncaab_games %>%
    filter(!home_team %in% nba_team_names, !away_team %in% nba_team_names)
}

# ---- Apply to each sport ----
value_nba <- calc_value_bets(
  nba_games,
  pyth_home_col = home_pyth_exp_143,
  pyth_away_col = away_pyth_exp_143,
  sport_label   = "NBA"
)

value_ncaab <- calc_value_bets(
  ncaab_games,
  pyth_home_col = home_pyth_winpct,
  pyth_away_col = away_pyth_winpct,
  sport_label   = "NCAAB"
)

value_nhl <- calc_value_bets(
  nhl_games,
  pyth_home_col = home_pyth_exp_dyn,
  pyth_away_col = away_pyth_exp_dyn,
  sport_label   = "NHL"
)

# ── Spread + Total bets ───────────────────────────────────────────────────────
spread_total_nba   <- calc_spread_total_bets(nba_games,   "NBA")
spread_total_ncaab <- calc_spread_total_bets(ncaab_games, "NCAAB")
spread_total_nhl   <- calc_spread_total_bets(nhl_games,   "NHL")

spread_total_all <- bind_rows(spread_total_nba, spread_total_ncaab, spread_total_nhl)

cat(sprintf("Spread/Total candidates — NBA: %d | NCAAB: %d | NHL: %d\n",
            nrow(spread_total_nba), nrow(spread_total_ncaab), nrow(spread_total_nhl)))

# ── Deduplicate spread/total to best book per game+bet_type+bet_team ──────────
spread_total_best <- spread_total_all %>%
  group_by(sport, game_date, bet_type, bet_team, home_team, away_team) %>%
  slice_max(bet_edge, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(desc(bet_edge))

# ── Combine ML + spread/total raw kelly, then flag "both" ML sides ────────────
value_all <- bind_rows(value_nba, value_ncaab, value_nhl) %>%
  filter(home_value | away_value) %>%
  mutate(
    value_side = case_when(
      home_value & away_value ~ "both",
      home_value              ~ "home",
      away_value              ~ "away",
      TRUE                    ~ NA_character_
    ),
    raw_kelly = case_when(
      value_side == "home" ~ home_kelly_q,
      value_side == "away" ~ away_kelly_q,
      value_side == "both" ~ pmax(home_kelly_q, away_kelly_q),
      TRUE                 ~ 0
    ),
    bet_team = case_when(
      value_side == "home" ~ home_team,
      value_side == "away" ~ away_team,
      value_side == "both" ~ paste(home_team, "+", away_team),
      TRUE                 ~ NA_character_
    ),
    bet_ml = case_when(
      value_side == "home" ~ home_ml,
      value_side == "away" ~ away_ml,
      TRUE                 ~ NA_real_
    ),
    bet_ev = case_when(
      value_side == "home" ~ home_ev,
      value_side == "away" ~ away_ev,
      TRUE                 ~ NA_real_
    ),
    bet_edge = case_when(
      value_side == "home" ~ home_edge,
      value_side == "away" ~ away_edge,
      TRUE                 ~ NA_real_
    ),
    implied_prob = 1 / bet_ml,
    open_time  = Sys.time(),   # ← ADD BELOW THIS LINE
    # ── Lifecycle fields ──────────────────────────────
    position_id   = make_position_id(sport, game_date, home_team,
                                     away_team, value_side, bookmaker_key),
    status        = "IDENTIFIED",
    placed_time   = as.POSIXct(NA),
    game_start    = game_start,   # TOA commence_time not in scope here
    settle_time   = as.POSIXct(NA),
    stake         = NA_real_,
    result        = NA_real_,
    cashout_value = NA_real_,
    hedge_time    = as.POSIXct(NA),
    hedge_book    = NA_character_,
    hedge_ml      = NA_real_,
    hedge_stake   = NA_real_,
    hedge_result  = NA_real_,
    clv_at_action = NA_real_,
    pnl           = NA_real_
  )

# ── Deduplicate ML to best book per game/team ─────────────────────────────────
value_best <- value_all %>%
  group_by(sport, game_date, bet_team) %>%
  slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(desc(bet_ev))

# ── Separate "both" cases for manual review ───────────────────────────────────
value_both <- value_best %>% 
  filter(value_side == "both") %>% 
  mutate(note = "⚠️ Both sides show value — verify before betting")

# --- COMBINED KELLY SCALING ---
all_raw_kelly <- c(value_best$raw_kelly, spread_total_best$raw_kelly,
                   value_soccer$raw_kelly,
                   value_mlb$raw_kelly, totals_mlb$raw_kelly)   # MLB added
total_combined_kelly <- sum(all_raw_kelly, na.rm = TRUE)
sf_combined          <- if (total_combined_kelly > BANKROLL_CAP) {
  BANKROLL_CAP / total_combined_kelly
} else { 1.0 }

value_best         <- value_best         %>% mutate(scaled_kelly = raw_kelly * sf_combined)
spread_total_best  <- spread_total_best  %>% mutate(scaled_kelly = raw_kelly * sf_combined)
value_soccer       <- value_soccer       %>% mutate(scaled_kelly = raw_kelly * sf_combined)  # <-- ADD THIS
value_mlb         <- value_mlb         %>% mutate(scaled_kelly = raw_kelly * sf_combined)  # ADD
totals_mlb        <- totals_mlb        %>% mutate(scaled_kelly = raw_kelly * sf_combined)  # ADD

mlb_log_path <- file.path("logs", paste0("mlb_bet_log_", Sys.Date(), ".csv"))
mlb_bet_log_new <- bind_rows(
  value_mlb  %>% mutate(bet_type = "ML",  bet_line = NA_real_),
  totals_mlb
) %>%
  mutate(log_date = Sys.Date(),
         result   = NA_character_,
         pnl      = NA_real_) %>%
  filter(!is.na(bet_ml)) %>%
  select(sport, log_date, game_date, open_time, home_team, away_team, bookmaker_key,
         bet_type, bet_team, bet_ml, bet_line, raw_kelly, scaled_kelly, result, pnl)

write_csv(mlb_bet_log_new, mlb_log_path)
cat("✅ MLB bets logged:", nrow(mlb_bet_log_new), "\n")


cat(sprintf("Combined picks: %d ML + %d ST | Total raw kelly: %.4f | Scale factor: %.4f | Cap triggered: %s\n",
            nrow(value_best), nrow(spread_total_best),
            total_combined_kelly, sf_combined,
            total_combined_kelly > BANKROLL_CAP))

cat("--- VALUE BETS (place these) ---\n")
value_best %>% 
  select(sport, game_date, bet_team, bookmaker_key, bet_ml, bet_ev, bet_edge, scaled_kelly) %>% 
  print(n = 25)

cat("--- BOTH SIDES FLAGGED (review manually) ---\n")
value_both %>% 
  select(sport, game_date, home_team, away_team, bookmaker_key, home_ml, away_ml, note) %>% 
  print(n = Inf)

cat("--- SPREAD/TOTAL VALUE BETS ---\n")
spread_total_best %>% 
  select(sport, game_date, home_team, away_team, bookmaker_key, bet_type, bet_team, 
         bet_line, bet_odds, expected_value, bet_edge_pts, bet_edge, scaled_kelly) %>% 
  print(n = 25)

# Write all logs
write_bet_log(value_best)
write_spread_total_log(spread_total_best)

# ---- Soccer bet log ----
soccer_log_path <- file.path("logs", paste0("soccer_bet_log_", Sys.Date(), ".csv"))

soccer_bet_log_new <- value_soccer %>%
  mutate(
    log_date    = Sys.Date(),
    result      = NA_character_,
    pnl         = NA_real_,
    close_price = NA_real_,
    close_time  = NA
  ) %>%
  select(sport, log_date, game_date, open_time,
         home_team, away_team, bookmaker_key,
         value_side, bet_team, bet_ml,
         home_novigprob, away_novigprob,
         home_pyth, away_pyth,
         home_ev, away_ev, bet_ev, home_edge, away_edge,
         raw_kelly, scaled_kelly,
         result, pnl, close_price, close_time)

write_csv(soccer_bet_log_new, soccer_log_path)
cat("\nSoccer bet log written:", soccer_log_path, "\n")
cat(nrow(soccer_bet_log_new), "soccer value bets logged\n")

# ============================================================
# RESULTS FETCHER — dynamic, runs for yesterday's games
# ============================================================

yesterday      <- Sys.Date() - 1
yesterday_str  <- format(yesterday, "%Y%m%d")   # e.g. "20260303"
log_dir        <- file.path(getwd(), "logs")
log_path       <- file.path(log_dir, paste0("bet_log_", yesterday, ".csv"))

# ---- NBA ----
nba_results_raw <- fromJSON(paste0(
  "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=",
  yesterday_str
))

nba_results <- map_dfr(
  seq_len(nrow(nba_results_raw$events)),
  function(i) {
    event <- nba_results_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    tibble(
      game_date  = as.Date(substr(event$date, 1, 10)),
      home_team  = teams$team$displayName[teams$homeAway == "home"],
      away_team  = teams$team$displayName[teams$homeAway == "away"],
      home_score = as.integer(teams$score[teams$homeAway == "home"]),
      away_score = as.integer(teams$score[teams$homeAway == "away"]),
      completed  = comp$status$type$completed
    )
  }
) %>% mutate(game_date = yesterday)

# ---- NHL ----
nhl_results_raw <- fromJSON(paste0(
  "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=",
  yesterday_str
))

nhl_results <- map_dfr(
  seq_len(nrow(nhl_results_raw$events)),
  function(i) {
    event <- nhl_results_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    tibble(
      game_date  = as.Date(substr(event$date, 1, 10)),
      home_team  = teams$team$displayName[teams$homeAway == "home"],
      away_team  = teams$team$displayName[teams$homeAway == "away"],
      home_score = as.integer(teams$score[teams$homeAway == "home"]),
      away_score = as.integer(teams$score[teams$homeAway == "away"]),
      completed  = comp$status$type$completed
    )
  }
) %>% mutate(game_date = yesterday)

# ---- NCAAB ----
ncaab_results_raw <- fromJSON(paste0(
  "https://site.api.espn.com/apis/site/v2/sports/basketball/",
  "mens-college-basketball/scoreboard?groups=50&limit=200&dates=",
  yesterday_str
))

ncaab_results <- map_dfr(
  seq_len(nrow(ncaab_results_raw$events)),
  function(i) {
    event <- ncaab_results_raw$events[i, ]
    comp  <- event$competitions[[1]][1, ]
    teams <- comp$competitors[[1]]
    tibble(
      game_date  = as.Date(substr(event$date, 1, 10)),
      home_team  = teams$team$displayName[teams$homeAway == "home"],
      away_team  = teams$team$displayName[teams$homeAway == "away"],
      home_score = as.integer(teams$score[teams$homeAway == "home"]),
      away_score = as.integer(teams$score[teams$homeAway == "away"]),
      completed  = comp$status$type$completed
    )
  }
) %>% mutate(game_date = yesterday)

cat("NBA games", format(yesterday), ":\n")
print(nba_results %>% filter(completed == TRUE))
cat("\nNHL games", format(yesterday), ":\n")
print(nhl_results %>% filter(completed == TRUE))
cat("\nNCAAB games", format(yesterday), "completed:", sum(ncaab_results$completed), "\n")

# ---- Soccer ----
fetch_espn_soccer_results <- function(target_date = Sys.Date() - 1) {
  map_dfr(seq_len(nrow(SOCCER_ESPN_SLUGS)), function(i) {
    league_label <- SOCCER_ESPN_SLUGS$league_label[i]
    slug         <- SOCCER_ESPN_SLUGS$espn_slug[i]
    
    url <- paste0(
      "http://site.api.espn.com/apis/site/v2/sports/soccer/",
      slug, "/scoreboard?dates=",
      format(target_date, "%Y%m%d")
    )
    
    raw <- tryCatch(fromJSON(url), error = function(e) {
      message("ESPN fetch failed: ", league_label, " — ", e$message)
      return(NULL)
    })
    
    if (is.null(raw) || !is.data.frame(raw$events) || nrow(raw$events) == 0) {
      return(tibble())
    }
    
    map_dfr(seq_len(nrow(raw$events)), function(j) {
      tryCatch({
        comp  <- raw$events$competitions[[j]]
        stype <- comp$status$type
        completed <- if ("completed" %in% names(stype)) {
          stype$completed
        } else {
          stype$name == "STATUS_FULL_TIME"
        }
        if (!isTRUE(completed)) return(tibble())
        
        teams <- comp$competitors[[1]]
        home  <- teams[teams$homeAway == "home", ]
        away  <- teams[teams$homeAway == "away", ]
        
        home_name <- normalize_espn_name(home$team$displayName, league_label)
        away_name <- normalize_espn_name(away$team$displayName, league_label)
        
        tibble(
          league       = league_label,
          game_date    = as.Date(substr(raw$events$date[j], 1, 10)),
          home_team    = home_name,
          away_team    = away_name,
          home_score   = as.integer(home$score),
          away_score   = as.integer(away$score),
          match_result = case_when(
            as.integer(home$score) > as.integer(away$score) ~ "home_win",
            as.integer(home$score) < as.integer(away$score) ~ "away_win",
            TRUE                                             ~ "draw"
          )
        )
      }, error = function(e) {
        message("Parse error: ", league_label, " event ", j, " — ", e$message)
        tibble()
      })
    })
  })
}

soccer_results_yesterday <- fetch_espn_soccer_results(target_date = yesterday)

# ── MLB results fetcher ───────────────────────────────────────────────────────
fetch_espn_mlb_results <- function(target_date = Sys.Date() - 1) {
  # Spring Training ends ~March 26; regular season ESPN endpoint
  # only covers regular season games — will return empty for preseason dates
  if (target_date < as.Date("2026-03-27")) {
    cat("MLB settler: skipping pre-season date", format(target_date), "\n")
    return(tibble())
  }
  url <- paste0(
    "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates=",
    format(target_date, "%Y%m%d")
  )
  raw <- tryCatch(fromJSON(url), error = function(e) {
    message("ESPN MLB fetch failed: ", e$message)
    return(NULL)
  })
  if (is.null(raw) || !is.data.frame(raw$events) || nrow(raw$events) == 0) {
    cat("No MLB results for", format(target_date), "\n")
    return(tibble())
  }
  map_dfr(seq_len(nrow(raw$events)), function(i) {
    tryCatch({
      comp  <- raw$events$competitions[[i]]
      stype <- comp$status$type
      completed <- isTRUE(stype$completed)
      if (!completed) return(tibble())
      teams     <- comp$competitors[[1]]
      home      <- teams[teams$homeAway == "home", ]
      away      <- teams[teams$homeAway == "away", ]
      tibble(
        game_date  = as.Date(substr(raw$events$date[i], 1, 10)),
        home_team  = home$team$displayName,
        away_team  = away$team$displayName,
        home_score = as.integer(home$score),
        away_score = as.integer(away$score),
        winner     = if_else(as.integer(home$score) > as.integer(away$score),
                             home$team$displayName, away$team$displayName)
      )
    }, error = function(e) {
      message("MLB parse error event ", i, ": ", e$message)
      tibble()
    })
  })
}

# ── MLB settler ───────────────────────────────────────────────────────────────
# Settles mlb_bet_log_*.csv files in-place.
# NOTE: MLB PnL is intentionally NOT wired into settle_paper_day yet.
# ── PARKING LOT (March 27) ────────────────────────────────────────────────────
# TODO: Create mlb_pnl_by_date from settled MLB logs (mirror soccer_pnl_by_date)
# TODO: Add mlb_pnl_by_date_arg parameter to settle_paper_day()
# TODO: Include mlb_pnl_by_date in all settle_paper_day() calls
# ─────────────────────────────────────────────────────────────────────────────
settle_mlb_log <- function(log_path, results_df) {
  if (!file.exists(log_path)) return(invisible(NULL))
  # ── Guard: no results available (pre-season, off-day, fetch failure) ────────
  if (is.null(results_df) || nrow(results_df) == 0) {
    cat(sprintf("⏭️  MLB settler: no results to score against — skipping %s\n",
                basename(log_path)))
    return(invisible(NULL))
  }
  
  log <- read_csv(log_path,
                  col_types = cols(result       = col_character(),
                                   pnl          = col_double(),
                                   game_date    = col_date(),
                                   bet_line     = col_double(),
                                   bet_ml       = col_double(),
                                   scaled_kelly = col_double()),
                  show_col_types = FALSE)
  
  unsettled <- log %>% filter(is.na(result))
  if (nrow(unsettled) == 0) return(invisible(NULL))
  
  scored <- unsettled %>%
    left_join(
      results_df %>%
        select(game_date, home_team, away_team, home_score, away_score, winner),
      by = c("game_date", "home_team", "away_team")
    ) %>%
    mutate(
      actual_total = home_score + away_score,
      result = case_when(
        is.na(home_score)                                  ~ NA_character_,
        bet_type == "OVER"  & actual_total > bet_line      ~ "W",
        bet_type == "OVER"  & actual_total <= bet_line     ~ "L",
        bet_type == "UNDER" & actual_total < bet_line      ~ "W",
        bet_type == "UNDER" & actual_total >= bet_line     ~ "L",
        bet_type == "ML"    & bet_team == winner           ~ "W",
        bet_type == "ML"    & bet_team != winner           ~ "L",
        TRUE                                               ~ NA_character_
      ),
      pnl = case_when(
        result == "W" ~ (bet_ml - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ NA_real_
      )
    ) %>%
    select(-home_score, -away_score, -actual_total, -winner)
  
  updated_log <- bind_rows(
    log %>% filter(!is.na(result)),
    scored
  ) %>% arrange(game_date, home_team)
  
  newly_settled <- scored %>% filter(!is.na(result))
  if (nrow(newly_settled) > 0) {
    cat(sprintf("Settled %d MLB bets in %s\n",
                nrow(newly_settled), basename(log_path)))
    print(newly_settled %>%
            select(sport, game_date, home_team, away_team,
                   bet_type, bet_team, bet_ml, bet_line, result, pnl))
    write_csv(updated_log, log_path)
  }
  
  invisible(newly_settled)
}

# ── Call the settler each run ─────────────────────────────────────────────────
mlb_results_yesterday <- fetch_espn_mlb_results(target_date = yesterday)

mlb_log_files <- list.files("logs",
                            pattern  = "mlb_bet_log_.*\\.csv",
                            full.names = TRUE)

mlb_settled_today <- map_dfr(mlb_log_files,
                             ~ settle_mlb_log(.x, mlb_results_yesterday))

cat(sprintf("\n=== MLB SETTLER ===\n"))
cat("Files scanned:", length(mlb_log_files), "\n")
cat("Newly settled:", nrow(mlb_settled_today), "bets\n")
# NOTE: MLB results are NOT included in paper trading until March 27 (see parking lot above)


# ============================================================
# FULL SOCCER SETTLER — settles all soccer logs for yesterday
# ============================================================

soccer_log_files <- list.files("logs",
                               pattern = "soccer_bet_log_.*\\.csv",
                               full.names = TRUE)

soccer_settled_today <- map_dfr(soccer_log_files, function(log_path) {
  if (!file.exists(log_path)) return(tibble())
  
  log <- read_csv(log_path,
                  col_types = cols(
                    result      = col_character(),
                    pnl         = col_double(),
                    close_price = col_double(),
                    game_date   = col_date()
                  ),
                  show_col_types = FALSE)
  
  unsettled <- log %>% filter(is.na(result))
  if (nrow(unsettled) == 0) return(tibble())
  
  # Extract league label from sport ("SOCCER-EPL" → "EPL")
  unsettled <- unsettled %>%
    mutate(league = sub("SOCCER-", "", sport))
  
  scored <- unsettled %>%
    left_join(
      soccer_results_yesterday %>%     # ← correct name
        select(league, game_date, home_team, away_team, match_result),
      by = c("league", "game_date", "home_team", "away_team")
    ) %>%
    mutate(
      result = case_when(
        is.na(match_result)                                      ~ NA_character_,
        value_side == "home_value" & match_result == "home_win" ~ "W",
        value_side == "draw_value"  & match_result == "draw"    ~ "W",
        value_side == "away_value" & match_result == "away_win" ~ "W",
        !is.na(match_result)                                     ~ "L",
        TRUE                                                     ~ NA_character_
      ),
      pnl = case_when(
        result == "W" ~ (bet_ml - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ NA_real_
      )
    ) %>%
    select(-league, -match_result)
  
  # Overwrite log with updated results
  updated_log <- bind_rows(
    log %>% filter(!is.na(result)),
    scored
  ) %>% arrange(game_date, home_team)
  
  write_csv(updated_log, log_path)
  
  scored %>% filter(!is.na(result))
})

cat(sprintf("\n=== SOCCER SETTLER ===\n"))
cat("Files scanned:", length(soccer_log_files), "\n")
cat("Newly settled:", nrow(soccer_settled_today), "bets\n")

if (nrow(soccer_settled_today) > 0) {
  print(soccer_settled_today %>%
          select(sport, game_date, home_team, away_team,
                 value_side, bet_team, bet_ml, result, pnl))
}


cat("\nSoccer results fetched:", nrow(nrow(soccer_results_yesterday)), "completed matches\n")
print(soccer_results_yesterday %>%
        filter(league == "EPL") %>%
        select(league, game_date, home_team, away_team,
               home_score, away_score, match_result))


# ---- Combine all results ----
all_results <- bind_rows(
  nba_results   %>% filter(completed == TRUE) %>% mutate(sport = "NBA"),
  nhl_results   %>% filter(completed == TRUE) %>% mutate(sport = "NHL"),
  ncaab_results %>% filter(completed == TRUE) %>% mutate(sport = "NCAAB")
) %>%
  mutate(winner = ifelse(home_score > away_score, home_team, away_team))

# ---- Load yesterday's bet log ----
# Handles both old format (has close_price) and new format (doesn't)
bet_log <- read_csv(log_path,
                    col_types = cols(
                      result    = col_character(),
                      pnl       = col_double(),
                      game_date = col_date(),
                      .default  = col_guess()
                    ),
                    show_col_types = FALSE)

# ---- Score settled bets ----
soccer_settled_today <- map_dfr(soccer_log_files,
                                ~ settle_soccer_log(.x, soccer_results_yesterday))

# Soccer PnL contribution for paper trading (by game_date)
soccer_pnl_by_date <- if (nrow(soccer_settled_today) > 0) {
  soccer_settled_today %>%
    filter(!is.na(result)) %>%
    group_by(game_date) %>%
    summarise(
      soccer_pnl   = sum(pnl, na.rm = TRUE),
      soccer_wins  = sum(result == "W"),
      soccer_losses = sum(result == "L"),
      .groups = "drop"
    )
} else {
  tibble(game_date = as.Date(character()),
         soccer_pnl = numeric(),
         soccer_wins = integer(),
         soccer_losses = integer())
}

cat("\nSoccer settled today:",
    sum(soccer_settled_today$result %in% c("W","L"), na.rm = TRUE),
    "bets\n")


bet_log_scored <- bet_log %>%
  left_join(
    all_results %>% select(sport, game_date, home_team, away_team, winner),
    by = c("sport", "game_date", "home_team", "away_team")
  ) %>%
  mutate(
    result = case_when(
      !is.na(winner) & bet_team == winner ~ "W",
      !is.na(winner) & bet_team != winner ~ "L",
      TRUE ~ result
    ),
    pnl = case_when(
      result == "W" ~ (bet_ml - 1) * scaled_kelly,
      result == "L" ~ -scaled_kelly,
      TRUE ~ pnl
    )
  ) %>%
  select(-winner)

# ---- Preview and save ----
cat("\nScored bets:\n")
print(bet_log_scored %>%
        filter(!is.na(result)) %>%
        select(sport, game_date, home_team, away_team,
               bet_team, bet_ml, scaled_kelly, result, pnl))

write_csv(bet_log_scored, log_path)
cat("\nBet log updated:", log_path, "\n")
cat("Total settled PnL:", round(sum(bet_log_scored$pnl, na.rm = TRUE), 6), "\n")
cat("Unsettled picks remaining:", sum(is.na(bet_log_scored$result)), "\n")

# ============================================================
# SPREAD/TOTAL SETTLER — runs after yesterday is defined
# ============================================================

spread_total_log_path <- file.path(log_dir,
                                   paste0("spread_total_log_", yesterday, ".csv"))

if (file.exists(spread_total_log_path)) {
  
  # AFTER
  st_log <- read_csv(spread_total_log_path,
                     col_types = cols(
                       result    = col_character(),
                       pnl       = col_double(),
                       game_date = col_date(),
                       .default  = col_guess()
                     ),
                     show_col_types = FALSE)
  
  
  st_log_scored <- st_log %>%
    left_join(
      all_results %>%
        select(sport, game_date, home_team, away_team, home_score, away_score),
      by = c("sport", "game_date", "home_team", "away_team")
    ) %>%
    mutate(
      actual_total = home_score + away_score,
      home_margin  = home_score - away_score,
      
      result = case_when(
        bet_type == "SPREAD" & bet_team == home_team &
          !is.na(home_score) ~ if_else(home_margin > -bet_line, "W", "L"),
        bet_type == "SPREAD" & bet_team == away_team &
          !is.na(away_score) ~ if_else(-home_margin > -bet_line, "W", "L"),
        bet_type == "OVER"  & !is.na(actual_total) ~
          if_else(actual_total > bet_line, "W", "L"),
        bet_type == "UNDER" & !is.na(actual_total) ~
          if_else(actual_total < bet_line, "W", "L"),
        TRUE ~ result
      ),
      
      pnl = case_when(
        result == "W" ~ (bet_odds - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ pnl
      )
    ) %>%
    select(-actual_total, -home_margin, -home_score, -away_score)
  
  cat("\nScored spread/total bets:\n")
  print(st_log_scored %>%
          filter(!is.na(result)) %>%
          select(sport, game_date, home_team, away_team,
                 bet_type, bet_team, bet_line, bet_odds,
                 scaled_kelly, result, pnl))
  
  write_csv(st_log_scored, spread_total_log_path)
  cat("Spread/total log updated:", spread_total_log_path, "\n")
  
  st_settled_pnl <- sum(st_log_scored$pnl, na.rm = TRUE)
  cat(sprintf("Spread/total settled PnL: %.6f\n", st_settled_pnl))
  
} else {
  cat("No spread/total log found for", format(yesterday), "\n")
  st_settled_pnl <- 0
}

# ============================================================
# PAPER TRADING TRACKER
# ============================================================

STARTING_BANKROLL <- 1000.00
paper_log_path    <- file.path(getwd(), "logs", "paper_trading_log.csv")

# ---- Initialize log if it doesn't exist ----
if (!file.exists(paper_log_path)) {
  paper_log_init <- tibble(
    date               = as.Date(character()),
    starting_bankroll  = numeric(),
    total_risked       = numeric(),
    settled_pnl_kelly  = numeric(),
    settled_pnl_dollar = numeric(),
    ending_bankroll    = numeric(),
    daily_roi          = numeric(),
    cumulative_roi     = numeric(),
    wins               = integer(),
    losses             = integer(),
    unsettled          = integer()
  )
  write_csv(paper_log_init, paper_log_path)
  cat("Paper trading log initialized.\n")
}

# ---- Load existing paper log ----
paper_log <- read_csv(paper_log_path,
                      col_types = cols(
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
                      ))

# ---- Determine current bankroll ----
current_bankroll <- if (nrow(paper_log) == 0) {
  STARTING_BANKROLL
} else {
  tail(paper_log$ending_bankroll, 1)
}

cat("Current paper bankroll: $", round(current_bankroll, 2), "\n")
cat("Daily risk cap (10%):   $", round(current_bankroll * 0.10, 2), "\n")

# ---- Score yesterday's bets in dollar terms ----
settle_paper_day <- function(ml_log_path, bankroll_at_open, st_log_path = NULL, 
                             log_date_override = NULL,
                             soccer_pnl_by_date_arg = NULL) {  # <-- NEW PARAMETER
  
  if (!file.exists(ml_log_path)) {
    cat("No bet log found for", ml_log_path, "\n")
    return(NULL)
  }
  
  # AFTER
  ml_log <- read_csv(ml_log_path,
                     col_types = cols(
                       result    = col_character(),
                       pnl       = col_double(),
                       game_date = col_date(),
                       .default  = col_guess()
                     ),
                     show_col_types = FALSE)
  
  
  ml_settled <- ml_log %>% filter(!is.na(result), result %in% c("W", "L"))
  
  # Load spread/total settled bets if path provided
  st_settled <- tibble(result = character(), pnl = double(), scaled_kelly = double())
  if (!is.null(st_log_path) && file.exists(st_log_path)) {
    # AFTER
    st_log <- read_csv(st_log_path,
                       col_types = cols(
                         result    = col_character(),
                         pnl       = col_double(),
                         game_date = col_date(),
                         .default  = col_guess()
                       ),
                       show_col_types = FALSE)
    
    st_settled <- st_log %>%
      filter(!is.na(result), result %in% c("W", "L")) %>%
      select(result, pnl, scaled_kelly)
  }
  
  all_settled <- bind_rows(
    ml_settled %>% select(result, pnl, scaled_kelly),
    st_settled
  )
  
  if (nrow(all_settled) == 0) {
    cat("No settled bets found in", ml_log_path, "\n")
    return(NULL)
  }
  
  all_settled <- all_settled %>%
    mutate(
      dollar_stake = scaled_kelly * bankroll_at_open,
      dollar_pnl   = pnl * bankroll_at_open
    )
  
  # ---- NEW: Soccer PnL for this date ----
  soccer_day_pnl_kelly  <- 0
  soccer_day_wins       <- 0L
  soccer_day_losses     <- 0L
  
  if (!is.null(soccer_pnl_by_date_arg) && nrow(soccer_pnl_by_date_arg) > 0) {
    this_date <- if (!is.null(log_date_override)) 
      as.Date(log_date_override) 
    else as.Date(unique(ml_log$log_date))
    soccer_row <- soccer_pnl_by_date_arg %>% filter(game_date == this_date)
    if (nrow(soccer_row) > 0) {
      soccer_day_pnl_kelly <- soccer_row$soccer_pnl[1]
      soccer_day_wins      <- soccer_row$soccer_wins[1]
      soccer_day_losses    <- soccer_row$soccer_losses[1]
    }
  }
  
  soccer_day_pnl_dollar <- soccer_day_pnl_kelly * bankroll_at_open
  
  tibble(
    date = if (!is.null(log_date_override)) as.Date(log_date_override) 
    else as.Date(unique(ml_log$log_date)),
    starting_bankroll  = bankroll_at_open,
    total_risked       = sum(all_settled$dollar_stake, na.rm = TRUE),
    settled_pnl_kelly  = sum(all_settled$pnl, na.rm = TRUE) + soccer_day_pnl_kelly,
    settled_pnl_dollar = sum(all_settled$dollar_pnl, na.rm = TRUE) + soccer_day_pnl_dollar,
    ending_bankroll    = round(bankroll_at_open +
                                 sum(all_settled$dollar_pnl, na.rm = TRUE) +
                                 soccer_day_pnl_dollar, 2),
    daily_roi          = (sum(all_settled$dollar_pnl, na.rm = TRUE) + soccer_day_pnl_dollar) /
      bankroll_at_open,
    cumulative_roi     = NA_real_,
    wins               = sum(all_settled$result == "W") + soccer_day_wins,
    losses             = sum(all_settled$result == "L") + soccer_day_losses,
    unsettled          = sum(is.na(ml_log$result))
  )
}

# ============================================================
# SOCCER BET SETTLER — settles in-place across all log files
# ============================================================

settle_soccer_log <- function(log_path, results_df) {
  if (!file.exists(log_path)) return(invisible(NULL))
  
  log <- read_csv(log_path,
                  col_types = cols(
                    result      = col_character(),
                    pnl         = col_double(),
                    game_date   = col_date(),
                    close_price = col_double()
                  ),
                  show_col_types = FALSE)
  
  unsettled <- log %>% filter(is.na(result))
  if (nrow(unsettled) == 0) return(invisible(NULL))
  
  # Extract league label from sport column ("SOCCER-EPL" → "EPL")
  unsettled <- unsettled %>%
    mutate(league = sub("SOCCER-", "", sport))
  
  scored <- unsettled %>%
    left_join(
      results_df %>% select(league, game_date, home_team, away_team, match_result),
      by = c("league", "game_date", "home_team", "away_team")
    ) %>%
    mutate(
      result = case_when(
        is.na(match_result)                                        ~ NA_character_,
        value_side == "home_value" & match_result == "home_win"   ~ "W",
        value_side == "draw_value" & match_result == "draw"       ~ "W",
        value_side == "away_value" & match_result == "away_win"   ~ "W",
        !is.na(match_result)                                       ~ "L",
        TRUE                                                       ~ NA_character_
      ),
      pnl = case_when(
        result == "W" ~ (bet_ml - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ NA_real_
      )
    ) %>%
    select(-league, -match_result)
  
  # Merge back with already-settled rows
  updated_log <- bind_rows(
    log %>% filter(!is.na(result)),
    scored
  ) %>%
    arrange(game_date, home_team)
  
  newly_settled <- scored %>% filter(!is.na(result))
  if (nrow(newly_settled) > 0) {
    cat(sprintf("Settled %d soccer bets in %s\n",
                nrow(newly_settled), basename(log_path)))
    print(newly_settled %>%
            select(sport, game_date, home_team, away_team,
                   value_side, bet_team, bet_ml, result, pnl))
    write_csv(updated_log, log_path)
  }
  
  invisible(newly_settled)
}


# ---- Backfill any missing historical days ----
backfill_dates <- as.Date(c("2026-03-02", "2026-03-03", "2026-03-04"))

for (i in seq_along(backfill_dates)) {
  bf_date <- backfill_dates[i]   # index into the vector — preserves Date class
  
  if (!bf_date %in% paper_log$date) {
    bf_ml_path <- file.path(getwd(), "logs", paste0("bet_log_", bf_date, ".csv"))
    bf_st_path <- file.path(getwd(), "logs", paste0("spread_total_log_", bf_date, ".csv"))
    
    bf_bankroll <- if (nrow(paper_log) == 0) {
      STARTING_BANKROLL
    } else {
      tail(paper_log$ending_bankroll, 1)
    }
    
    bf_row <- settle_paper_day(bf_ml_path, bf_bankroll,
                               st_log_path          = bf_st_path,
                               log_date_override    = bf_date,
                               soccer_pnl_by_date_arg = soccer_pnl_by_date)
    
    if (!is.null(bf_row)) {
      paper_log <- bind_rows(paper_log, bf_row) %>% arrange(date)
      cat("Backfilled:", format(bf_date), "\n")
    } else {
      cat("No data for:", format(bf_date), "\n")
    }
  } else {
    cat("Already logged:", format(bf_date), "\n")
  }
}


# ---- Add/update yesterday (only if not already backfilled above) ----
if (!yesterday %in% paper_log$date) {
  yesterday_bankroll <- if (nrow(paper_log) == 0) {
    STARTING_BANKROLL
  } else {
    tail(paper_log$ending_bankroll, 1)
  }
  
  yesterday_row <- settle_paper_day(log_path, yesterday_bankroll,
                                    st_log_path           = spread_total_log_path,
                                    log_date_override     = yesterday,
                                    soccer_pnl_by_date_arg = soccer_pnl_by_date)
  
  if (!is.null(yesterday_row)) {
    paper_log <- paper_log %>%
      filter(date != yesterday) %>%
      bind_rows(yesterday_row) %>%
      arrange(date)
    cat("Yesterday (", format(yesterday), ") paper log updated.\n")
  }
}


# ---- Recalculate cumulative ROI ----
paper_log <- paper_log %>%
  arrange(date) %>%
  mutate(
    cumulative_roi = (ending_bankroll - STARTING_BANKROLL) / STARTING_BANKROLL
  )

# ---- Save updated log ----
write_csv(paper_log, paper_log_path)

# ---- Print dashboard ----
cat("\n========================================\n")
cat("       PAPER TRADING DASHBOARD\n")
cat("========================================\n")
cat("Starting bankroll:  $", formatC(STARTING_BANKROLL,    format="f", digits=2), "\n")
cat("Current bankroll:   $", formatC(tail(paper_log$ending_bankroll, 1), format="f", digits=2), "\n")
cat("Total P&L:          $", formatC(tail(paper_log$ending_bankroll, 1) - STARTING_BANKROLL, format="f", digits=2), "\n")
cat("Cumulative ROI:     ",  round(tail(paper_log$cumulative_roi, 1) * 100, 2), "%\n")
cat("Overall record:     ",  sum(paper_log$wins), "W -", sum(paper_log$losses), "L\n")
cat("Days tracked:       ",  nrow(paper_log), "\n")
cat("========================================\n\n")

cat("Daily breakdown:\n")
options(pillar.sigfig = 7)
print(paper_log %>%
        select(date, starting_bankroll, total_risked,
               settled_pnl_dollar, ending_bankroll,
               daily_roi, wins, losses, unsettled) %>%
        mutate(
          starting_bankroll  = formatC(starting_bankroll,  format = "f", digits = 2),
          total_risked       = formatC(total_risked,        format = "f", digits = 2),
          settled_pnl_dollar = formatC(settled_pnl_dollar,  format = "f", digits = 2),
          ending_bankroll    = formatC(ending_bankroll,     format = "f", digits = 2),
          daily_roi          = paste0(round(daily_roi * 100, 3), "%")
        ))



