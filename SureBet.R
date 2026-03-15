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
#
# ── BOOKMAKER DISPLAY NAME ARCHITECTURE (completed 2026-03-13) ────────────────
# BOOK_DISPLAY_NAMES built dynamically from live API response each run (~line 181).
# API returns bookmaker_key (e.g. "espnbet") + display name (e.g. "theScore Bet").
# All sport pipelines carry bookmaker_name through to final_picks_clean Book col.
# Challenger: bookmaker_key = "espnbet", display = "theScore Bet" (hardcoded
#   since Challenger odds come from xlsx, not TOA API).
# ATP/WTA: best_home_book/best_away_book tracked via which.min() so Book shows
#   which specific book had the best price for each side.
# Fallback: coalesce(bookmaker_name, bookmaker_key) in final_picks_clean handles
#   any sport/row where bookmaker_name is NA.
#
# TODO (Monday, post-Selection Sunday): Convert sim_tournament() into a
#   March Madness NCAAB bracket calculator.
#   - Feed the 64-team bracket (seedings + regions) into sim_tournament()
#   - Replace Elo with Pythagorean win% (pyth_winpct) from ncaab_standings
#   - Output: each team's probability to reach each round + win championship
#   - Wire into value bet filter vs tournament futures odds on sportsbooks
#
# TODO (HIGH PRIORITY): Game start times — reliable tip times for all sports
#   Problem 1 — TOA midnight UTC sentinel: TOA returns "YYYY-MM-DDT00:00:00Z"
#     for games where tip time is not yet confirmed (common in NCAAB tournaments
#     and NBA). These display as 08:00 PM ET, which is technically correct but
#     meaningless. Fix: detect game_start == as.POSIXct(paste0(game_date,"T00:00:00Z"),
#     tz="UTC") and replace with NA (displays as TBD) until real time is known.
#     Explore ESPN scoreboard API as fallback for confirmed tip times.
#   Problem 2 — Challenger times in local tz: Challenger game_start is built
#     from the xlsx time column as local time (no tz set). with_tz() in
#     final_picks_clean then misinterprets it as UTC, shifting the time by 4-5h.
#     Fix: set tz="America/New_York" when constructing game_start in the
#     Challenger picks_raw block (~line 2027), or add a sport-aware tz
#     branch in final_picks_clean.
#   Priority note: start times are critical for batch betting, customer-facing
#     picks delivery, and any future parlay/same-game parlay features.
#
# TODO (future): Find a reliable Challenger API to replace manual TENDATAUPLOAD.xlsx.
#   - ATP/WTA Challenger tour has no official free API as of March 2026.
#   - Candidates to evaluate: tennisabstract.com data exports, RapidAPI tennis,
#     or sportsdata.io when budget allows.
#   - Once API found: rebuild challenger pipeline with automatic bracket fetch,
#     re-enable sim_tournament() for Challengers, and retire manual xlsx workflow.
#
# TODO (SOCCER — next week): Per-team draw rate weighting in model_draw_prob
#   Current approach: model_draw_prob = league_draw_rate (flat constant per league)
#   Better approach: weight by each team's individual draw tendency, exactly as in
#   Big5Odds spreadsheet H(W%) formula:
#     draw_alloc = league_draw_rate × (home_P(D%) / (home_P(D%) + away_P(D%)))
#   where P(D%) = team's actual draws / games_played this season
#   This is already calculated in your manual spreadsheet and verified correct.
#   Implementation:
#     1. FotMob standings already return home_draws / home_games_played and
#        away_draws / away_games_played — these are in soccer_standings_all
#     2. Carry home_draw_rate and away_draw_rate through soccer_games join
#     3. In calc_soccer_value_bets(), replace:
#          model_draw_prob = draw_rate
#        with:
#          team_draw_alloc = draw_rate * (home_draw_rate / (home_draw_rate + away_draw_rate))
#          model_draw_prob = team_draw_alloc
#     4. Also update DC engine draw_adv to use team-weighted draw prob
#   Expected impact: games with high-draw teams (e.g. two 30%+ draw teams) will
#   show higher model_draw_prob, improving DC recommendation precision.
#   Reference: Big5Odds col H(W%) formula verified 2026-03-14.
#
# TODO (NFL / NCAAF season — before first spread bet): Key number push probabilities
#   - Current spread model treats margins as continuous → assigns zero probability
#     to exact integer landings. Reasonable for NBA/NCAAB (high-scoring, diffuse).
#     MATERIALLY WRONG for NFL/NCAAF where key numbers cluster strongly.
#   - NFL historical margin frequencies: 3 (~9-10%), 7 (~5-6%), 10, 6, 4, 1 are
#     all meaningfully elevated vs. uniform distribution.
#   - Fix: replace continuous edge calc with discrete P(win)/P(push)/P(lose):
#       EV = P(win)*(odds-1) - P(lose)*1 + P(push)*0
#     P(push) at the key number compresses P(win)+P(lose) → raises true win rate
#     on resolved bets above raw model probability.
#   - Same logic applies to NFL/NCAAF TOTALS: key totals (41, 43, 44, 51) show
#     clustering. Half-point hooks on totals should be evaluated the same way as
#     spreads — the hook eliminates push risk and is worth a calculable premium.
#   - Implementation: build a key_number_lookup tribble with historical push rates
#     by sport and inject into calc_spread_total_bets() before EV calculation.
#   - For now: NBA/NCAAB/NHL continuous approximation is defensible. Do not add
#     complexity until NFL pipeline is being built.
#
# ── REMINDER (week of ~March 16) ─────────────────────────────────────────────
# ATP/WTA new tournaments start Sunday/Monday ~March 16-17.
# When the draws are released (usually day before first round):
#   1. Add full draw to TENDATAUPLOAD.xlsx — same Matches tab format as Challenger
#   2. The bracket sim will automatically pick it up — no code changes needed
#   3. Best value: add the draw BEFORE Round 1 when path-dependency edge is largest
#   4. After Round 1, mid-tournament market has corrected — sim still useful but
#      single-match Elo is adequate fallback
# ─────────────────────────────────────────────────────────────────────────────
#
# ── GUI / FRONTEND ROADMAP ────────────────────────────────────────────────────
# Current: Shiny dashboard (surebet_dashboard.R) — internal use only.
# Use Shiny while engine cleanup continues. Do NOT invest in Shiny layout.
#
# Stage 2 — Static web dashboard (do this next, when ready)
#   - Add write_json() exports to SureBet.R (daily_picks, paper_log, value_bets)
#   - Build standalone HTML/CSS/JS dashboard reading those JSON files
#   - No server required — opens in any browser, works on mobile if responsive
#   - THIS is where layout/design decisions get locked in
#   - Forces definition of data contracts (columns, formats) before app work
#
# Stage 3 — Hosted web app
#   - Host Stage 2 static dashboard (Netlify / GitHub Pages / VPS)
#   - Add Plumber (R) or FastAPI (Python) layer to serve picks on a schedule
#   - Now a real URL anyone can hit
#
# Stage 4 — Mobile app (two paths from Stage 3)
#   - PWA (recommended first): add manifest to Stage 3 site → installs like
#     an app on iOS/Android, no app store, shares all web code
#   - React Native (if native feel / push notifications needed): hits Stage 3 API
#
# Key principle: SureBet.R engine stays R throughout.
#   Frontend evolves independently once outputs are JSON not just CSV.
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
library(rvest)
library(zoo)
library(furrr)   # parallel map_dfr for odds fetch speedup

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
# ── FETCH CONTROL ─────────────────────────────────────────────────────────────
# Set FETCH_ODDS <- FALSE to skip the API fetch and reuse cached multi_odds.
# Use this when debugging downstream code to avoid burning API quota.
# Requires multi_odds to already exist in the R session from a prior run.
# Set back to TRUE for any production run or when odds data needs refreshing.
FETCH_ODDS <- TRUE
# ──────────────────────────────────────────────────────────────────────────────
books  <- c("fanduel", "draftkings", "espnbet", "hardrockbet", "fanatics", "bet365")

# Auto-detect ALL active tennis keys — never edit again
tennis_keys <- toa_sports(all_sports = TRUE) %>%
  filter(str_detect(key, "tennis"), active == TRUE) %>%
  pull(key)
sports <- c("basketball_nba", "basketball_ncaab", "icehockey_nhl",
            "soccer_epl", "soccer_germany_bundesliga", "soccer_italy_serie_a",
            "soccer_france_ligue_one", "soccer_spain_la_liga", "soccer_usa_mls",
            "soccer_uefa_champs_league", "soccer_uefa_europa_league",
            tennis_keys)   # ← auto-populated every run
# TODO (March 27): Add "baseball_mlb" here and remove the
# MLB supplemental fetch block (MLB_SPORT_KEY preseason workaround)

if (FETCH_ODDS) {
  # Parallel fetch — 4-6x faster than serial map_dfr.
  # furrr::future_map_dfr runs each sport key in a separate R worker.
  # possibly() returns an empty tibble on any error/timeout — no crash.
  # Workers = 4 is safe for TOA rate limits; bump to 6 if quota allows.
  plan(multisession, workers = min(4L, length(sports)))
  safe_fetch <- possibly(
    ~ suppressWarnings(
        toa_sports_odds(
          sport_key = .x,
          regions   = "us,us2",
          markets   = "h2h,spreads,totals"
        ) %>%
          mutate(sport_key = .x)
      ),
    otherwise = tibble()
  )
  multi_odds <- future_map_dfr(sports, safe_fetch, .progress = TRUE)
  plan(sequential)   # release workers immediately after fetch
  cat(sprintf("\u2705 Odds fetched: %d rows across %d sports\n",
              nrow(multi_odds), length(sports)))
} else {
  if (!exists("multi_odds")) stop("FETCH_ODDS=FALSE but multi_odds not found. Run once with FETCH_ODDS=TRUE first.")
  cat(sprintf("ℹ️  FETCH_ODDS=FALSE — reusing cached multi_odds (%d rows)\n", nrow(multi_odds)))
}

# ============================================================
# Start runs at this point to avoid unnecessary calls
# ============================================================

multi_odds_filtered <- multi_odds %>%
  filter(bookmaker_key %in% books)

multi_odds_raw <- multi_odds_filtered

# Build bookmaker display name lookup dynamically from live API data.
# The API returns both bookmaker_key (e.g. "espnbet") and bookmaker
# (e.g. "theScore Bet") — extract the mapping once here so all downstream
# display uses are consistent and automatically pick up any new books.
BOOK_DISPLAY_NAMES <- multi_odds %>%
  filter(!is.na(bookmaker_key), !is.na(bookmaker)) %>%
  distinct(bookmaker_key, bookmaker) %>%
  deframe()   # named character vector: key -> display name

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
  "Texas A&M-CC Islanders",           "Texas A&M-Corpus Christi Islanders",
  # NCAAB additions (from 2026-03-12 diagnostic)
  "Grand Canyon Antelopes",           "Grand Canyon Antelopes",
  "UT-Arlington Mavericks",           "UT Arlington Mavericks",
  "CSU Northridge Matadors",          "Cal State Northridge Matadors",
  "San Diego St Aztecs",              "San Diego State Aztecs",
  "CSU Fullerton Titans",             "Cal State Fullerton Titans",
  "GW Revolutionaries",               "George Washington Revolutionaries",
  "Florida St Seminoles",             "Florida State Seminoles",
  "Loyola (Chi) Ramblers",            "Loyola Chicago Ramblers",
  "Kennesaw St Owls",                 "Kennesaw State Owls",
  "Colorado St Rams",                 "Colorado State Rams",
  "San José St Spartans",             "San José State Spartans",
  # NCAAB additions (from 2026-03-13 diagnostic)
  # TOA sends unaccented "San Jose State Spartans"; hoopR uses accented é
  "San Jose State Spartans",          "San José State Spartans",
  # hoopR includes "A&M" in Prairie View full name; Sam Houston dropped "State" in 2023
  # Grand Canyon: hoopR may not carry standings for this small WAC program
  "Prairie View Panthers",            "Prairie View A&M Panthers",
  "Michigan St Spartans",             "Michigan State Spartans",
  "Missouri St Bears",                "Missouri State Bears",
  "Sam Houston St Bearkats",          "Sam Houston Bearkats",
  "Cal Baptist Lancers",              "California Baptist Lancers",
  # NCAAB additions (from 2026-03-14 diagnostic)
  "Wichita St Shockers",              "Wichita State Shockers"
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
  
  # ── Dedup assertion: incoming df must have 1 row per game/side ───────────────
  # Catches pipeline dedup failures before they corrupt the log.
  dup_check <- new_rows %>%
    count(sport, game_date, home_team, away_team, value_side) %>%
    filter(n > 1)
  if (nrow(dup_check) > 0) {
    warning(sprintf(
      "write_bet_log: %d duplicate game/side combos detected in incoming df — keeping best EV only.\n",
      nrow(dup_check)
    ))
    new_rows <- new_rows %>%
      group_by(sport, game_date, home_team, away_team, value_side) %>%
      slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
      ungroup()
  }
  
  if (file.exists(log_path)) {
    existing <- read_csv(log_path,
                         col_types = cols(result    = col_character(),
                                          pnl       = col_double(),
                                          game_date = col_date(),
                                          log_date  = col_date(),
                                          .default  = col_guess()),
                         show_col_types = FALSE) %>%
      mutate(result = as.character(result))   # ← ADD: coerce legacy double NA to character NA
    new_only <- new_rows %>%
      filter(!position_id %in% existing$position_id) %>%
      mutate(result = as.character(result))
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
  
  # ── Dedup assertion: one row per game/bet_type/bet_team ──────────────────────
  dup_check_st <- new_rows %>%
    count(sport, game_date, home_team, away_team, bet_type, bet_team) %>%
    filter(n > 1)
  if (nrow(dup_check_st) > 0) {
    warning(sprintf(
      "write_spread_total_log: %d duplicate combos in incoming df — keeping best edge only.\n",
      nrow(dup_check_st)
    ))
    new_rows <- new_rows %>%
      group_by(sport, game_date, home_team, away_team, bet_type, bet_team) %>%
      slice_max(bet_edge, n = 1, with_ties = FALSE) %>%
      ungroup()
  }
  
  if (file.exists(log_path)) {
    existing <- read_csv(log_path,
                         col_types = cols(result    = col_character(),
                                          pnl       = col_double(),
                                          game_date = col_date(),
                                          log_date  = col_date(),
                                          .default  = col_guess()),
                         show_col_types = FALSE)
    new_only <- new_rows %>%
      filter(!position_id %in% existing$position_id) %>%
      mutate(result = as.character(result))
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

# ── NCAAB join diagnostic (Bug #8) ───────────────────────────────────────────
# Surfaces teams that have odds but no standings match (pyth will be NA → bet dropped).
# Add any mismatches found to name_crosswalk at the top of the script.
ncaab_toa_teams <- bind_rows(
  odds_ncaab_wide %>% distinct(team_name = home_team),
  odds_ncaab_wide %>% distinct(team_name = away_team)
) %>% distinct()

ncaab_standings_teams <- ncaab_standings %>% distinct(team_name = team_display_name)

ncaab_unmatched_toa <- anti_join(ncaab_toa_teams, ncaab_standings_teams, by = "team_name")
ncaab_na_pyth_games <- ncaab_games %>%
  filter(is.na(home_pyth_winpct) | is.na(away_pyth_winpct)) %>%
  select(game_date, home_team, away_team,
         home_pyth_winpct, away_pyth_winpct) %>%
  distinct()

cat("\n── NCAAB name mismatches ────────────────────────────────────────────────\n")
cat("TOA names with no standings match (add to name_crosswalk):\n")
print(ncaab_unmatched_toa)
cat(sprintf("Games with NA pyth (will be dropped from value search): %d\n",
            nrow(ncaab_na_pyth_games)))
if (nrow(ncaab_na_pyth_games) > 0) print(ncaab_na_pyth_games)
cat("─────────────────────────────────────────────────────────────────────────\n\n")
# ─────────────────────────────────────────────────────────────────────────────

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
  "Nice",                       "UEL",    "Nice",
  # ── UCL additions (2026-03-12) ────────────────────────────────────────────
  "Sporting Lisbon",            "UCL",    "Sporting CP",
  # ── UEL additions (2026-03-12) ────────────────────────────────────────────
  "Porto",                      "UEL",    "FC Porto",
  "SC Braga",                   "UEL",    "Braga"
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

# ── Soccer join diagnostic (Bug #9) ──────────────────────────────────────────
# The filter(!is.na(home_pyth_winpct), !is.na(away_pyth_winpct)) in soccer_games
# silently drops games where a team has no FotMob standings match.
# This block surfaces exactly which team names are failing the join so you can
# add them to SOCCER_NAME_MAP.
soccer_games_pre_filter <- soccer_h2h_wide %>%
  left_join(
    soccer_standings_all %>% select(league, team, pyth_winpct),
    by = c("league", "home_team_norm" = "team")
  ) %>%
  rename(home_pyth_winpct = pyth_winpct) %>%
  left_join(
    soccer_standings_all %>% select(league, team, pyth_winpct),
    by = c("league", "away_team_norm" = "team")
  ) %>%
  rename(away_pyth_winpct = pyth_winpct)

soccer_na_home <- soccer_games_pre_filter %>%
  filter(is.na(home_pyth_winpct)) %>%
  distinct(league, team = home_team_norm)
soccer_na_away <- soccer_games_pre_filter %>%
  filter(is.na(away_pyth_winpct)) %>%
  distinct(league, team = away_team_norm)
soccer_unmatched <- bind_rows(soccer_na_home, soccer_na_away) %>%
  distinct() %>% arrange(league, team)

n_dropped <- nrow(soccer_h2h_wide) - nrow(soccer_games)
cat(sprintf("Games dropped (NA pyth after FotMob join): %d\n", n_dropped))
cat("Unmatched team names (add to SOCCER_NAME_MAP):\n")
print(soccer_unmatched)
cat("─────────────────────────────────────────────────────────────────────────\n\n")
# ─────────────────────────────────────────────────────────────────────────────

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
        model_draw_prob, draw_rate,
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
        model_draw_prob, draw_rate,
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
        model_draw_prob, draw_rate,
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

# ── Soccer Double Chance Decision Engine ──────────────────────────────────────
# Double chance covers two of three 1X2 outcomes:
#   1X = Home win OR Draw  |  X2 = Draw OR Away win  |  12 = Home OR Away
#
# TOA double_chance market requires per-event endpoint (not bulk fetch) —
# not practical for our pipeline. We calculate DC fair value from our 1X2
# model probabilities instead, which is the correct approach.
#
# Decision framework mirrors Big5Odds spreadsheet (DrawAdv / TmAdv columns):
#   draw_adv = model_draw_prob - league_draw_rate  (is draw elevated vs. avg?)
#   DC_ML_EV_OVERRIDE_THRESHOLD = 0.15  (take ML only if ML_EV > DC_EV by >15%)
#
# Rules:
#   1. draw_value + home/away_value → DC (team+draw) unless ML EV clearly dominates
#   2. draw_value + draw_adv > 0 → always recommend Draw or DC+Draw
#   3. single-side ML value only → straight ML

DC_ML_EV_OVERRIDE_THRESHOLD <- 0.15   # Take ML if ML_EV exceeds DC_EV by this margin

soccer_dc_recommendations <- value_soccer %>%
  group_by(sport, game_date, home_team, away_team) %>%
  summarise(
    home_value  = any(value_side == "home_value"),
    away_value  = any(value_side == "away_value"),
    draw_value  = any(value_side == "draw_value"),
    home_ev     = suppressWarnings(max(bet_ev[value_side == "home_value"],  na.rm = TRUE)),
    away_ev     = suppressWarnings(max(bet_ev[value_side == "away_value"],  na.rm = TRUE)),
    draw_ev     = suppressWarnings(max(bet_ev[value_side == "draw_value"],  na.rm = TRUE)),
    model_home  = first(home_pyth),
    model_away  = first(away_pyth),
    model_draw  = first(model_draw_prob),
    draw_rate   = first(draw_rate),
    best_book   = first(bookmaker_key),
    .groups = "drop"
  ) %>%
  mutate(
    home_ev = ifelse(is.infinite(home_ev) | is.nan(home_ev), NA_real_, home_ev),
    away_ev = ifelse(is.infinite(away_ev) | is.nan(away_ev), NA_real_, away_ev),
    draw_ev = ifelse(is.infinite(draw_ev) | is.nan(draw_ev), NA_real_, draw_ev),

    # DrawAdv: is this game's model draw prob above the league average?
    draw_adv          = coalesce(model_draw, draw_rate) - coalesce(draw_rate, 0),

    # DC fair win probabilities (sum of two 1X2 model probs)
    dc_home_draw_prob = coalesce(model_home, 0) + coalesce(model_draw, coalesce(draw_rate, 0)),
    dc_away_draw_prob = coalesce(model_away, 0) + coalesce(model_draw, coalesce(draw_rate, 0)),

    dc_recommendation = case_when(
      # Rule 1a: home + draw value → DC home+draw (unless ML dominates)
      home_value & draw_value & !is.na(home_ev) & !is.na(draw_ev) &
        (home_ev - dc_home_draw_prob) <= DC_ML_EV_OVERRIDE_THRESHOLD
        ~ paste0(home_team, " or Draw (DC)"),

      # Rule 1b: away + draw value → DC away+draw (unless ML dominates)
      away_value & draw_value & !is.na(away_ev) & !is.na(draw_ev) &
        (away_ev - dc_away_draw_prob) <= DC_ML_EV_OVERRIDE_THRESHOLD
        ~ paste0(away_team, " or Draw (DC)"),

      # Rule 1c: ML EV clearly dominates — take straight home ML
      home_value & draw_value & !is.na(home_ev) & !is.na(draw_ev) &
        (home_ev - dc_home_draw_prob) > DC_ML_EV_OVERRIDE_THRESHOLD
        ~ paste0(home_team, " ML (EV dominates DC)"),

      # Rule 1d: ML EV clearly dominates — take straight away ML
      away_value & draw_value & !is.na(away_ev) & !is.na(draw_ev) &
        (away_ev - dc_away_draw_prob) > DC_ML_EV_OVERRIDE_THRESHOLD
        ~ paste0(away_team, " ML (EV dominates DC)"),

      # Rule 2: draw value + draw rate above league avg → Draw or DC+Draw
      draw_value & !is.na(draw_adv) & draw_adv > 0
        ~ "Draw (rate above league avg)",

      # Rule 3: draw value only, draw rate at/below avg → straight Draw
      draw_value & !home_value & !away_value
        ~ "Draw",

      # Rule 4: single ML value, no draw conflict → straight ML
      home_value & !draw_value ~ paste0(home_team, " ML"),
      away_value & !draw_value ~ paste0(away_team, " ML"),

      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(dc_recommendation)) %>%
  select(sport, game_date, home_team, away_team,
         home_value, draw_value, away_value,
         draw_adv, dc_recommendation,
         home_ev, draw_ev, away_ev)

if (nrow(soccer_dc_recommendations) > 0) {
  cat("\n--- Soccer Double Chance / Bet Type Recommendations ---\n")
  cat(nrow(soccer_dc_recommendations), "games with actionable DC guidance\n\n")
  print(soccer_dc_recommendations, n = Inf)
  cat("────────────────────────────────────────────────────────────\n\n")
}

# ============================================================
# SACKMANN TOURNAMENT SIMULATOR — single-elimination bracket
# ============================================================
# Pure R port of JeffSackmann/781922 (gist.github.com/JeffSackmann/781922)
# Replaces TA spreadsheet simulation probs for Challenger pipeline.
# Also used as optional enrichment for ATP/WTA draws when full bracket known.
#
# CONSTANTS (tune after backtesting):
TENNIS_ELO_E  <- 1.1     # Sackmann's exponent; 1.0 = standard Elo, >1 = more separation
TENNIS_SIMS   <- 50000   # 50k sims; ~0.3s in R; raise to 100k for finals week

#' Head-to-head win probability from Elo ratings
#' @param elo_a  Numeric Elo for player A
#' @param elo_b  Numeric Elo for player B
#' @param e      Exponent (default TENNIS_ELO_E = 1.1)
#' @return       P(A beats B)
calc_h2h_prob <- function(elo_a, elo_b, e = TENNIS_ELO_E) {
  a <- as.numeric(elo_a); b <- as.numeric(elo_b)
  (a^e) / ((a^e) + (b^e))
}

#' Single-elimination tournament simulator (Sackmann method)
#'
#' @param draw_df  Data frame with columns:
#'                   player  — character, player name (draw order = bracket position)
#'                   elo     — numeric Elo rating (surface-appropriate)
#'                 Rows MUST be in draw order (1v2, 3v4, … bracket pairing).
#'                 Draw size must be a power of 2 (4, 8, 16, 32, 64, 128).
#' @param sims     Number of simulations (default TENNIS_SIMS)
#' @param e        Elo exponent (default TENNIS_ELO_E)
#' @return         Tibble: player, elo, sim_win_prob (P reaching final and winning),
#'                 plus sim_reach_sf, sim_reach_f for semis/finals reach rates.
#'                 Also includes sim_next_match_prob = P(winning immediate next match).
sim_tournament <- function(draw_df, sims = TENNIS_SIMS, e = TENNIS_ELO_E) {

  players  <- draw_df$player
  elo_vec  <- setNames(draw_df$elo, draw_df$player)
  n        <- length(players)

  # Validate draw size — must be power of 2
  if (n < 2 || bitwAnd(n, n - 1L) != 0L) {
    warning("sim_tournament: draw size must be a power of 2 (got ", n, ")")
    return(
      draw_df %>%
        mutate(sim_win_prob       = NA_real_,
               sim_reach_f        = NA_real_,
               sim_reach_sf       = NA_real_,
               sim_next_match_prob = NA_real_)
    )
  }

  n_rounds <- log2(n)

  # Result accumulators — indexed by player name
  wins_count  <- setNames(integer(n), players)   # tournament wins
  final_count <- setNames(integer(n), players)   # final appearances
  sf_count    <- setNames(integer(n), players)   # semifinal appearances
  next_count  <- setNames(integer(n), players)   # immediate next match wins

  for (sim in seq_len(sims)) {
    current_round <- players   # draw order preserved → correct bracket pairing

    round_num <- 0L
    while (length(current_round) > 1) {
      round_num  <- round_num + 1L
      n_matches  <- length(current_round) / 2
      next_round <- character(n_matches)

      for (i in seq_len(n_matches)) {
        p1  <- current_round[2*i - 1]
        p2  <- current_round[2*i]
        wp1 <- calc_h2h_prob(elo_vec[p1], elo_vec[p2], e)
        if (runif(1) < wp1) {
          next_round[i] <- p1
          if (round_num == 1L) next_count[p1] <- next_count[p1] + 1L
        } else {
          next_round[i] <- p2
          if (round_num == 1L) next_count[p2] <- next_count[p2] + 1L
        }
      }

      # Track semis/finals appearances
      if (length(next_round) == 4) {
        for (p in next_round) sf_count[p] <- sf_count[p] + 1L
      }
      if (length(next_round) == 2) {
        for (p in next_round) final_count[p] <- final_count[p] + 1L
      }
      if (length(next_round) == 1) {
        wins_count[next_round[1]] <- wins_count[next_round[1]] + 1L
      }

      current_round <- next_round
    }
  }

  draw_df %>%
    mutate(
      sim_win_prob        = wins_count[player]  / sims,
      sim_reach_f         = final_count[player] / sims,
      sim_reach_sf        = sf_count[player]    / sims,
      sim_next_match_prob = next_count[player]  / sims
    )
}

#' Convenience wrapper: simulate a SINGLE matchup (no full draw needed)
#' Equivalent to 2-player bracket — consistent with sim_tournament math.
#' Replaces the bare Elo formula for ATP/WTA single-game bets.
#' @param elo_home  Home player Elo
#' @param elo_away  Away player Elo
#' @param hfa_elo   Home field Elo bonus (default 25 pts — standard TA adjustment)
#' @param sims      Simulations (lower default fine for 2-player — math is exact)
#' @return          list(home_prob, away_prob)  — from analytical formula (sims unused for 2p)
sim_matchup <- function(elo_home, elo_away, hfa_elo = 25, e = TENNIS_ELO_E) {
  home_prob <- calc_h2h_prob(elo_home + hfa_elo, elo_away, e)
  list(home_prob = home_prob, away_prob = 1 - home_prob)
}

cat(sprintf("✅ Sackmann simulator loaded (e=%.2f, sims=%d)\n",
            TENNIS_ELO_E, TENNIS_SIMS))

# ============================================================
# TENNIS PIPELINE — ATP + WTA Elo Value Bets
# ============================================================

# ── 1. Scrape live ATP Elo ratings ───────────────────────────────────────────
atp_elo_raw <- tryCatch(
  read_html("https://tennisabstract.com/reports/atp_elo_ratings.html") %>%
    html_table(fill = TRUE),
  error = function(e) {
    message("⚠️  ATP Elo scrape failed: ", e$message)
    NULL
  }
)

atp_elo_clean <- if (!is.null(atp_elo_raw)) {
  atp_elo_raw[[3]] %>%
    janitor::clean_names() %>%
    mutate(
      player = str_replace_all(player, "\u00A0", " "),
      player = str_squish(player),
      across(c(h_elo, c_elo, g_elo), as.numeric)
    ) %>%
    select(player, h_elo, c_elo, g_elo)
} else {
  tibble(player = character(), h_elo = numeric(),
         c_elo = numeric(), g_elo = numeric())
}

# ── 2. WTA Elo ratings (identical structure, different URL) ───────────────────
wta_elo_raw <- tryCatch(
  read_html("https://tennisabstract.com/reports/wta_elo_ratings.html") %>%
    html_table(fill = TRUE),
  error = function(e) {
    message("⚠️  WTA Elo scrape failed: ", e$message)
    NULL
  }
)

wta_elo_clean <- if (!is.null(wta_elo_raw)) {
  wta_elo_raw[[3]] %>%
    janitor::clean_names() %>%
    mutate(
      player = str_replace_all(player, "\u00A0", " "),
      player = str_squish(player),
      across(c(h_elo, c_elo, g_elo), as.numeric)
    ) %>%
    select(player, h_elo, c_elo, g_elo)
} else {
  tibble(player = character(), h_elo = numeric(),
         c_elo = numeric(), g_elo = numeric())
}

cat(sprintf("ATP Elo loaded: %d players | WTA Elo loaded: %d players\n",
            nrow(atp_elo_clean), nrow(wta_elo_clean)))

# ── 3. Tennis h2h odds — best book per matchup ───────────────────────────────
tennis_h2h <- multi_odds_filtered %>%
  filter(str_detect(sport_key, "tennis"), market_key == "h2h") %>%
  mutate(game_date = as.Date(substr(commence_time, 1, 10))) %>%
  group_by(game_date, sport_key, home_team, away_team) %>%
  summarise(
    books_home   = list(bookmaker_key[outcomes_name == home_team]),
    books_away   = list(bookmaker_key[outcomes_name == away_team]),
    odds_home    = list(outcomes_price[outcomes_name == home_team]),
    odds_away    = list(outcomes_price[outcomes_name == away_team]),
    game_start   = as.POSIXct(first(commence_time), tz = "UTC"),   # earliest tip
    .groups      = "drop"
  ) %>%
  filter(lengths(odds_home) > 0, lengths(odds_away) > 0)

tennis_best_odds <- tennis_h2h %>%
  mutate(
    best_home_ml   = map_dbl(odds_home, min),
    best_away_ml   = map_dbl(odds_away, min),
    # Book that had the best (lowest decimal = best value) odds for each side
    best_home_book = map2_chr(books_home, odds_home,
                              ~ .x[which.min(.y)] %||% NA_character_),
    best_away_book = map2_chr(books_away, odds_away,
                              ~ .x[which.min(.y)] %||% NA_character_),
    # Parse sport_key → readable tournament label
    # e.g. "tennis_atp_indian_wells" → "Indian Wells"
    tournament = sport_key %>%
      str_remove("^tennis_(atp_|wta_)") %>%
      str_replace_all("_", " ") %>%
      str_to_title()
  ) %>%
  select(game_date, sport_key, tournament, home_team, away_team,
         best_home_ml, best_away_ml, best_home_book, best_away_book, game_start)

cat(sprintf("Tennis matchups with odds: %d\n", nrow(tennis_best_odds)))

# ── 4. Surface mapping (sport_key → Elo column) ───────────────────────────────
# Hardcourt → h_elo | Clay → c_elo | Grass → g_elo
# Add tournament patterns here as new events appear in tennis_keys
calc_tennis_value <- function(best_odds_df, elo_df, tour_label) {

  surface_col <- case_when(
    str_detect(best_odds_df$sport_key, "indian_wells|miami|australia|us_open|canada|cincinnati|tokyo|shanghai|vienna|paris|doha|dubai|rotterdam|dallas|montpellier|memphis|acapulco|houston|washington|beijing|astana|metz|chengdu|zhuhai|st_petersburg|nur_sultan|antwerp|stockholm|moscow|sofia|lincoln|adelaide|auckland|pune|newport|atlanta|winston|los_angeles|san_diego|umag|kitzbuhel|gstaad|bastad|hamburg|bogota") ~ "h_elo",
    str_detect(best_odds_df$sport_key, "monte_carlo|rome|madrid|roland_garros|barcelona|lyon|geneva|marrakech|estoril|munich|dusseldorf|hamburg|buenos_aires|rio|santiago|cordoba|sao_paulo|marbella|leon|istanbul") ~ "c_elo",
    str_detect(best_odds_df$sport_key, "wimbledon|queens|eastbourne|halle|stuttgart|newport_grass|s_hertogenbosch") ~ "g_elo",
    TRUE ~ "h_elo"   # default hardcourt
  )

  best_odds_df %>%
    mutate(surface_elo_col = surface_col) %>%
    left_join(elo_df %>% select(player, h_elo, c_elo, g_elo),
              by = c("home_team" = "player")) %>%
    left_join(elo_df %>% select(player, h_elo, c_elo, g_elo),
              by = c("away_team" = "player"),
              suffix = c("_home", "_away")) %>%
    mutate(
      home_elo = case_when(
        surface_elo_col == "h_elo" ~ h_elo_home,
        surface_elo_col == "c_elo" ~ c_elo_home,
        TRUE                       ~ g_elo_home
      ),
      away_elo = case_when(
        surface_elo_col == "h_elo" ~ h_elo_away,
        surface_elo_col == "c_elo" ~ c_elo_away,
        TRUE                       ~ g_elo_away
      ),
      # sim_matchup() uses Sackmann exponent (TENNIS_ELO_E=1.1) + 25pt HFA
      # Analytically equivalent to 2-player bracket sim — consistent with Challenger sims
      elo_diff        = home_elo - away_elo + 25,   # kept for display/diagnostics
      model_home_prob = map2_dbl(home_elo, away_elo,
                                 ~ sim_matchup(.x, .y, hfa_elo = 25)$home_prob),
      home_ev         = (best_home_ml - 1) * model_home_prob -
                        (1 - model_home_prob),
      away_ev         = (best_away_ml - 1) * (1 - model_home_prob) -
                        model_home_prob,
      # Quarter Kelly per side
      home_kelly_q    = pmax(
        ((best_home_ml - 1) * model_home_prob - (1 - model_home_prob)) /
          (best_home_ml - 1), 0) / 4,
      away_kelly_q    = pmax(
        ((best_away_ml - 1) * (1 - model_home_prob) - model_home_prob) /
          (best_away_ml - 1), 0) / 4
    ) %>%
    select(game_date, sport_key, tournament, home_team, away_team,
           best_home_ml, best_away_ml, best_home_book, best_away_book, game_start,
           home_elo, away_elo, elo_diff,
           model_home_prob, home_ev, away_ev,
           home_kelly_q, away_kelly_q)
}

# ── 5. Split ATP / WTA, run Elo pipeline, recombine ──────────────────────────
atp_best_odds <- tennis_best_odds %>%
  filter(!str_detect(sport_key, "wta"))   # ATP keys never contain "wta"

wta_best_odds <- tennis_best_odds %>%
  filter(str_detect(sport_key, "wta"))

atp_with_elo <- if (nrow(atp_best_odds) > 0 && nrow(atp_elo_clean) > 0)
  calc_tennis_value(atp_best_odds, atp_elo_clean, "ATP") else tibble()

wta_with_elo <- if (nrow(wta_best_odds) > 0 && nrow(wta_elo_clean) > 0)
  calc_tennis_value(wta_best_odds, wta_elo_clean, "WTA") else tibble()

tennis_with_elo <- bind_rows(
  atp_with_elo %>% mutate(tour = "ATP"),
  wta_with_elo %>% mutate(tour = "WTA")
)

# ── 6. Elo join diagnostic — surfaces unmatched player names ─*Updated 3/11/26─
if (nrow(tennis_with_elo) > 0) {
  tennis_na_elo <- tennis_with_elo %>%
    filter(is.na(home_elo) | is.na(away_elo)) %>%
    select(tour, game_date, home_team, away_team, home_elo, away_elo)
  
  if (nrow(tennis_na_elo) > 0) {
    cat("\n── Tennis Elo mismatches (add name fixes above) ─────────────────────────\n")
    print(tennis_na_elo)
    cat("─────────────────────────────────────────────────────────────────────────\n\n")
  }
}


# ── 7. Value filter + Kelly sizing ───────────────────────────────────────────
tennis_value_bets <- tennis_with_elo %>%
  filter(!is.na(home_elo), !is.na(away_elo)) %>%
  filter(home_ev > EV_GATE | away_ev > EV_GATE) %>%
  mutate(
    sport      = paste0(tour, " - ",
                        coalesce(tournament, sport_key %>%
                                   str_remove("^tennis_(atp_|wta_)") %>%
                                   str_replace_all("_", " ") %>%
                                   str_to_title())),
    value_side = case_when(
      home_ev > EV_GATE & away_ev > EV_GATE ~ "both",
      home_ev > EV_GATE                     ~ "home_value",
      TRUE                                  ~ "away_value"
    ),
    bet_team   = case_when(
      value_side == "home_value" ~ home_team,
      value_side == "away_value" ~ away_team,
      TRUE                       ~ paste(home_team, "+", away_team)
    ),
    bet_ml     = case_when(
      value_side == "home_value" ~ best_home_ml,
      value_side == "away_value" ~ best_away_ml,
      TRUE                       ~ NA_real_
    ),
    bookmaker_key = case_when(
      value_side == "home_value" ~ best_home_book,
      value_side == "away_value" ~ best_away_book,
      TRUE                       ~ coalesce(best_home_book, best_away_book)
    ),
    bet_ev     = case_when(
      value_side == "home_value" ~ home_ev,
      value_side == "away_value" ~ away_ev,
      TRUE                       ~ pmax(home_ev, away_ev)
    ),
    raw_kelly  = case_when(
      value_side == "home_value" ~ home_kelly_q,
      value_side == "away_value" ~ away_kelly_q,
      TRUE                       ~ pmax(home_kelly_q, away_kelly_q)
    ),
    open_time     = Sys.time(),
    position_id   = make_position_id(sport, game_date,
                                     home_team, away_team,
                                     value_side, "best_book"),
    status        = "IDENTIFIED",
    placed_time   = as.POSIXct(NA),
    game_start    = if ("game_start" %in% names(.)) game_start else as.POSIXct(NA),
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
  arrange(desc(bet_ev))

cat(sprintf("\n--- Tennis Value Bets (ATP: %d | WTA: %d) ---\n",
            sum(tennis_value_bets$tour == "ATP", na.rm = TRUE),
            sum(tennis_value_bets$tour == "WTA", na.rm = TRUE)))
print(tennis_value_bets %>%
        select(sport, game_date, home_team, away_team,
               bet_team, bet_ml, bet_ev, raw_kelly))


# ============================================================
# TENNIS CHALLENGER PIPELINE — TENDATAUPLOAD.xlsx
# ============================================================
# Data source: SUREBET_DIR/TENDATAUPLOAD.xlsx
#   • Matches tab  — bracket matchups, odds, round-progression probs
#   • TEN ELO tab  — combined ATP+WTA surface Elo (replaces rvest scrape)
#
# Column layout (Matches tab, data_only values):
#   A = player name (with seeding/nationality)
#   B = decimal odds (blank = no market yet)
#   C = current-round survival prob  (0 = eliminated, 1 = advanced, 0<x<1 = active matchup)
#   D = next-round survival prob     (used as model prob when C=1)
#   E = round+2 survival prob
#   F = round+3 survival prob        (last non-NA col = win-tournament prob)
#   R = tournament name (Sport col)
#   S = match date (only on the "action" row)
#   U = event string "Player A vs Player B"
#   V = E(W%) — spreadsheet-computed model prob (mirrors our logic below)
#   W = Implied — no-vig book prob (already computed)
#   X = E(W%)-Implied — edge (already computed)
#
# Round-progression logic (fully automatic — no manual copy-paste needed):
#   C = 0           → player eliminated → skip
#   C = 1, D = 0    → advanced but next opponent TBD, no odds → skip
#   C = 1, D > 0    → advanced; upcoming matchup; model_prob = D
#   0 < C < 1       → active matchup this round; model_prob = C
#   odds blank      → no market posted yet → skip

challenger_xlsx <- file.path(SUREBET_DIR, "TENDATAUPLOAD.xlsx")

# ── 1. Load TEN ELO tab — used for Elo verification ──────────────────────────
challenger_elo <- if (file.exists(challenger_xlsx)) {
  tryCatch(
    read_xlsx(challenger_xlsx, sheet = "TEN ELO") %>%
      rename(player = Player, elo = Elo,
             h_elo = hElo, c_elo = cElo, g_elo = gElo) %>%
      mutate(player = str_replace_all(player, "\u00A0", " ") %>% str_squish()) %>%
      select(player, elo, h_elo, c_elo, g_elo),
    error = function(e) {
      message("⚠️  TEN ELO tab load failed: ", e$message)
      tibble(player = character(), elo = numeric(),
             h_elo = numeric(), c_elo = numeric(), g_elo = numeric())
    }
  )
} else {
  tibble(player = character(), elo = numeric(),
         h_elo = numeric(), c_elo = numeric(), g_elo = numeric())
}

cat(sprintf("TEN ELO loaded: %d players\n", nrow(challenger_elo)))

# ── 2. Load + parse Matches tab ──────────────────────────────────────────────
# Direct read of spreadsheet-computed columns — no Elo sim needed for Challengers.
# The Matches tab already contains:
#   col[21] = E(W%)          — tournament win probability (model_prob)
#   col[22] = Implied        — no-vig book probability
#   col[23] = E(W%)-Implied  — edge (model_prob minus implied)
#   col[1]  = decimal odds   (blank = no market posted)
#   col[16] = Action         — recommended bet player (non-null = value side)
#   col[17] = Sport/tournament name
#   col[18] = Date
#   col[19] = Time
#   col[20] = Event string "Player A vs Player B"
#
# NOTE: sim_tournament() is retained in this file for future use as a
#   March Madness NCAAB bracket calculator (see Parking Lot).
tennis_picks <- if (file.exists(challenger_xlsx)) {

  raw_matches <- read_xlsx(challenger_xlsx, sheet = "Matches",
                           col_names = FALSE,
                           skip = 1)            # skip unusable header row

  colnames(raw_matches) <- c(
    "player", "odds", "prob_c", "prob_d", "prob_e", "prob_f",
    paste0("col", 7:11),
    "col12", "col13", "model_prob_v_alt", "implied_alt", "event_pair",
    "action_flag", "tournament", "date_raw", "time_raw",
    "player_short", "model_prob_v", "implied_v", "edge_v"
  )

  parsed_pairs <- raw_matches %>%
    # Drop sentinel/header rows and fully empty rows
    filter(!is.na(player), !player %in% c("Player", ""),
           !is.na(tournament)) %>%
    mutate(
      odds       = suppressWarnings(as.numeric(odds)),
      model_prob = suppressWarnings(as.numeric(model_prob_v)),
      implied    = suppressWarnings(as.numeric(implied_v)),
      edge       = suppressWarnings(as.numeric(edge_v)),
      # Date: readxl returns POSIXct or numeric serial depending on cell format
      date_raw = {
        if (inherits(date_raw, "POSIXct") || inherits(date_raw, "Date")) {
          as.Date(date_raw)
        } else {
          d <- suppressWarnings(as.numeric(date_raw))
          d[is.na(d) | d < 32874 | d > 49673] <- NA_real_
          as.Date(d, origin = "1899-12-30")
        }
      },
      # Forward-fill navigation columns
      tournament = zoo::na.locf(tournament, na.rm = FALSE),
      event_pair = zoo::na.locf(event_pair, na.rm = FALSE),
      date_raw   = zoo::na.locf(date_raw,   na.rm = FALSE),
      # Parse time_raw (e.g. "2:00 PM", "14:00") into a clock string
      # Forward-fill so every player row inherits the match time
      time_raw   = zoo::na.locf(time_raw,   na.rm = FALSE),
      time_parsed = suppressWarnings(
        case_when(
          str_detect(as.character(time_raw), "^\\d{1,2}:\\d{2}\\s?(AM|PM|am|pm)$") ~
            format(strptime(as.character(time_raw), "%I:%M %p"), "%H:%M"),
          str_detect(as.character(time_raw), "^\\d{2}:\\d{2}$") ~
            as.character(time_raw),
          TRUE ~ NA_character_
        )
      )
    ) %>%
    # Keep only rows with valid odds and a valid E(W%) from the spreadsheet
    filter(!is.na(odds), odds > 1,
           !is.na(model_prob), model_prob > 0,
           !is.na(event_pair)) %>%
    group_by(tournament, event_pair) %>%
    mutate(
      game_date   = {
        d <- suppressWarnings(max(date_raw, na.rm = TRUE))
        if (is.infinite(d) || all(is.na(date_raw))) as.Date(NA) else as.Date(d)
      },
      home_player = str_trim(str_extract(event_pair, "^.+?(?= vs )")),
      away_player = str_trim(str_extract(event_pair, "(?<= vs ).+$"))
    ) %>%
    ungroup() %>%
    filter(!is.na(game_date))

  cat(sprintf("Challenger spreadsheet: %d matchup rows loaded\n", nrow(parsed_pairs)))

  # ── EV filter + Kelly ────────────────────────────────────────────────────
  picks_raw <- parsed_pairs %>%
    filter(!is.na(model_prob), model_prob > 0,
           !is.na(odds), odds > 1) %>%
    mutate(
      sport            = "TENNIS-CHALLENGER",
      sport_tournament = paste("CHA -", tournament),
      bet_team         = player,
      bet_ml           = odds,
      ta_model_prob    = model_prob,   # direct from spreadsheet
      bet_ev           = (bet_ml - 1) * model_prob - (1 - model_prob),
      raw_kelly        = pmax(0, (bet_ml - 1) * model_prob -
                               (1 - model_prob)) / (4 * (bet_ml - 1)),
      open_time        = Sys.time(),
      position_id      = paste0("CHALL_", game_date, "_",
                                str_replace_all(player, "[ ()]", "_")),
      status           = "IDENTIFIED",
      book             = "espnbet",        # bookmaker_key
      bookmaker_display = "theScore Bet",   # display name
      placed_time      = as.POSIXct(NA),
      # Build game_start from date_raw + time_parsed (no tz assumed — local time)
      game_start       = as.POSIXct(
        if_else(!is.na(time_parsed),
                paste(as.character(game_date), time_parsed),
                NA_character_)
      ),
      settle_time      = as.POSIXct(NA),
      stake            = NA_real_,
      result           = NA_character_,
      cashout_value    = NA_real_,
      hedge_time       = as.POSIXct(NA),
      hedge_book       = NA_character_,
      hedge_ml         = NA_real_,
      hedge_stake      = NA_real_,
      hedge_result     = NA_real_,
      clv_at_action    = NA_real_,
      pnl              = NA_real_
    ) %>%
    filter(bet_ev > EV_GATE, bet_ev <= EV_CAP)

  # ── Alignment: model_prob vs implied (no-vig) ────────────────────────────
  picks_with_align <- picks_raw %>%
    mutate(
      prob_diff = case_when(
        is.na(implied) ~ NA_real_,
        TRUE           ~ abs(model_prob - implied)
      ),
      alignment = case_when(
        is.na(implied)   ~ "⚠️ No implied (odds missing)",
        prob_diff < 0.08 ~ "✅ Elite",
        prob_diff < 0.18 ~ "✅ Good",
        prob_diff < 0.30 ~ "⚠️ Check",
        TRUE             ~ "⚠️ Large gap"
      )
    ) %>%
    select(sport, sport_tournament, game_date, open_time,
           home_player, away_player, bet_team,
           bet_ml, model_prob, ta_model_prob,
           bet_ev, raw_kelly,
           position_id, status, book, bookmaker_display,
           prob_diff, alignment,
           placed_time, game_start, settle_time, stake,
           result, cashout_value, hedge_time, hedge_book,
           hedge_ml, hedge_stake, hedge_result, clv_at_action, pnl)

  picks_with_align

} else {
  message("⚠️  Challenger xlsx not found — skipping: ", challenger_xlsx)
  tibble()
}


# ── Large-gap alignment diagnostic ──────────────────────────────────────────
if (nrow(tennis_picks) > 0) {
  large_gap <- tennis_picks %>% filter(str_detect(alignment, "Large gap|Check"))
  if (nrow(large_gap) > 0) {
    cat(sprintf("⚠️  %d challenger picks with large model/implied divergence — review before betting:\n",
                nrow(large_gap)))
    print(large_gap %>% select(sport_tournament, game_date, home_player, away_player,
                                bet_team, model_prob, bet_ml, alignment))
  }
}

# ── 3. Output ─────────────────────────────────────────────────────────────────
if (nrow(tennis_picks) > 0) {
  cat(sprintf("\n🎾 Challenger: %d value bets (>%.0f%% EV) | %d elite | %d good\n",
              nrow(tennis_picks), EV_GATE * 100,
              sum(tennis_picks$alignment == "✅ Elite", na.rm = TRUE),
              sum(tennis_picks$alignment == "✅ Good",  na.rm = TRUE)))
  print(tennis_picks %>%
          arrange(desc(bet_ev)) %>%
          select(sport_tournament, bet_team, bet_ml,
                 model_prob, prob_diff, bet_ev, alignment) %>%
          head(10))
} else {
  cat("ℹ️  No Challenger value bets this run.\n")
}

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

# ── Preseason guard: ensure odds_mlb always has expected schema ───────────────
# TOA returns no MLB preseason odds before ~March 26. The filtered tibble
# comes back with 0 rows AND 0 columns, crashing downstream mutate/pivot.
# Scaffold guarantees the pipeline runs cleanly (0 value bets) until March 27.
if (nrow(odds_mlb) == 0 || !("home_team" %in% names(odds_mlb))) {
  cat("i  MLB odds empty - inserting schema scaffold (preseason, expected pre-March 27)\n")
  odds_mlb <- tibble(
    game_date      = as.Date(character()),
    home_team      = character(),
    away_team      = character(),
    bookmaker_key  = character(),
    market_key     = character(),
    outcomes_name  = character(),
    outcomes_price = double(),
    outcomes_point = double()
  )
}

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

# -----Updated 3/11/26
totals_mlb_wide <- odds_mlb %>%
  filter(market_key == "totals", !is.na(outcomes_point)) %>%  # Key: skip missing lines
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

# ── 4) Value bets (h2h + totals) — inline EV, no calc_value_bets() ───────────
value_mlb <- mlb_games %>%
  filter(!is.na(home_ml), !is.na(away_ml)) %>%
  mutate(
    sport        = "MLB",
    home_ev      = (home_ml - 1) * home_h2h_prob - (1 - home_h2h_prob),
    away_ev      = (away_ml - 1) * (1 - home_h2h_prob) - home_h2h_prob,
    home_kelly_q = pmax(((home_ml - 1) * home_h2h_prob -
                           (1 - home_h2h_prob)) / (home_ml - 1), 0) / 4,
    away_kelly_q = pmax(((away_ml - 1) * (1 - home_h2h_prob) -
                           home_h2h_prob) / (away_ml - 1), 0) / 4
  ) %>%
  filter(home_ev > EV_GATE | away_ev > EV_GATE) %>%
  mutate(
    value_side = case_when(
      home_ev > EV_GATE & away_ev > EV_GATE ~ "both",
      home_ev > EV_GATE                     ~ "home",
      away_ev > EV_GATE                     ~ "away",
      TRUE                                  ~ NA_character_
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
      TRUE                 ~ pmax(home_ev, away_ev)
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
  arrange(desc(bet_ev)) %>%
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
      # ── Spread edges ──────────────────────────────────────────────────────────
      # expected_spread > 0 means model expects home team to win by that margin.
      # home_spread_outcomes_point is negative for home favorites (e.g. -12.5).
      # Edge = how many pts the model's margin beats the spread FROM THE BETTOR'S
      # perspective — i.e. does home cover their negative line?
      #
      # Home cover: home wins by MORE than abs(home_line).
      #   home_spread_edge_pts = expected_spread - abs(home_line)
      #                        = expected_spread + home_spread_outcomes_point
      #   (home_line is negative, so adding it subtracts — correct direction)
      #
      # Away cover: away wins OR home wins by LESS than abs(home_line).
      #   away_spread_edge_pts = abs(home_line) - expected_spread
      #                        = -(expected_spread + home_spread_outcomes_point)
      #   Away line (away_spread_outcomes_point) is positive mirror of home line.
      home_spread_edge_pts =  expected_spread + home_spread_outcomes_point,
      away_spread_edge_pts = -(expected_spread + home_spread_outcomes_point),
      
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

# ============================================================
# WNBA PIPELINE — PLACEHOLDER
# ============================================================
# Copy-paste NBA when ready (ESPN API key identical, hoopR same source).
# Focus: ML + spreads. Season starts ~May.
# value_wnba        <- tibble()   # uncomment + replace with pipeline
# spread_total_wnba <- tibble()   # uncomment + replace with pipeline
value_wnba        <- tibble(raw_kelly = numeric())
spread_total_wnba <- tibble(raw_kelly = numeric())

# ============================================================
# NFL PIPELINE — PLACEHOLDER
# ============================================================
# Copy-paste NBA when ready (spread/total focus; ML less relevant).
# Standings source: nflreadr::load_standings(). Season starts ~Sep.
# value_nfl        <- tibble()   # uncomment + replace with pipeline
# spread_total_nfl <- tibble()   # uncomment + replace with pipeline
value_nfl        <- tibble(raw_kelly = numeric())
spread_total_nfl <- tibble(raw_kelly = numeric())

# ============================================================
# NCAAF PIPELINE — PLACEHOLDER
# ============================================================
# Copy-paste NCAAB when ready (team totals focus; Pythagorean same structure).
# Standings source: cfbfastR::load_cfb_standings(). Season starts ~Aug.
# value_ncaaf        <- tibble()   # uncomment + replace with pipeline
# spread_total_ncaaf <- tibble()   # uncomment + replace with pipeline
value_ncaaf        <- tibble(raw_kelly = numeric())
spread_total_ncaaf <- tibble(raw_kelly = numeric())

# --- COMBINED KELLY SCALING ---
all_raw_kelly <- c(value_best$raw_kelly, spread_total_best$raw_kelly,
                   value_soccer$raw_kelly,
                   value_mlb$raw_kelly, totals_mlb$raw_kelly,
                   tennis_value_bets$raw_kelly,
                   tennis_picks$raw_kelly,
                   value_wnba$raw_kelly, spread_total_wnba$raw_kelly,    # WNBA placeholder
                   value_nfl$raw_kelly,  spread_total_nfl$raw_kelly,     # NFL placeholder
                   value_ncaaf$raw_kelly, spread_total_ncaaf$raw_kelly)  # NCAAF placeholder
total_combined_kelly <- sum(all_raw_kelly, na.rm = TRUE)
sf_combined          <- if (total_combined_kelly > BANKROLL_CAP) {
  BANKROLL_CAP / total_combined_kelly
} else { 1.0 }

value_best          <- value_best          %>% mutate(scaled_kelly = raw_kelly * sf_combined)
spread_total_best   <- spread_total_best   %>% mutate(scaled_kelly = raw_kelly * sf_combined)
value_soccer        <- value_soccer        %>% mutate(scaled_kelly = raw_kelly * sf_combined)
value_mlb           <- value_mlb           %>% mutate(scaled_kelly = raw_kelly * sf_combined)
totals_mlb          <- totals_mlb          %>% mutate(scaled_kelly = raw_kelly * sf_combined)
tennis_value_bets   <- tennis_value_bets   %>% mutate(scaled_kelly = raw_kelly * sf_combined)  # Tennis added
tennis_picks        <- if (nrow(tennis_picks) > 0)
  tennis_picks %>% mutate(scaled_kelly = raw_kelly * sf_combined) else tennis_picks  # Challenger added

# ── Unified picks dataframe — one row per bet across all sports ───────────────
# Common columns only; used by cap_daily_bets() and daily_picks log.
# ── Soccer home/away note ──────────────────────────────────────────────────────
# Most books display soccer with the AWAY team listed first (visually left).
# Our pipeline stores home_team / away_team correctly per FotMob/TOA convention.
# The "Home" and "Away" columns in the daily picks sheet reflect our data
# (home team hosts the match). Books will show these reversed — keep that in mind.
# ──────────────────────────────────────────────────────────────────────────────

all_picks_df <- bind_rows(

  # ── ML bets (NBA / NCAAB / NHL) ─────────────────────────────────────────────
  value_best %>%
    mutate(bet_type      = "ML",
           bet_line      = NA_real_,
           bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
           game_start    = if ("game_start" %in% names(.)) game_start
                           else as.POSIXct(NA)) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── Spread / Total bets (NBA / NCAAB / NHL) ──────────────────────────────────
  spread_total_best %>%
    mutate(
      bet_type  = bet_type,   # already "SPREAD" / "OVER" / "UNDER"
      bet_team  = case_when(
        bet_type == "OVER"  ~ paste("Over",  bet_line),
        bet_type == "UNDER" ~ paste("Under", bet_line),
        TRUE                ~ bet_team
      ),
      bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
      game_start = if ("game_start" %in% names(.)) game_start
                   else as.POSIXct(NA)
    ) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml = bet_odds,
           bet_ev = bet_edge, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── Soccer ML bets ───────────────────────────────────────────────────────────
  value_soccer %>%
    mutate(bet_type      = "ML",
           bet_line      = NA_real_,
           bookmaker_key  = if ("bookmaker_key" %in% names(.)) bookmaker_key
                            else NA_character_,
           bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
           game_start    = if ("game_start" %in% names(.)) game_start
                           else as.POSIXct(commence_time, tz = "UTC")) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── MLB ML bets ──────────────────────────────────────────────────────────────
  value_mlb %>%
    mutate(bet_type      = "ML",
           bet_line      = NA_real_,
           bookmaker_key  = if ("bookmaker_key" %in% names(.)) bookmaker_key
                            else NA_character_,
           bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
           game_start    = as.POSIXct(NA)) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── MLB Totals ───────────────────────────────────────────────────────────────
  totals_mlb %>%
    mutate(
      bet_type      = bet_type,
      bet_team      = case_when(
        bet_type == "OVER"  ~ paste("Over",  bet_line),
        bet_type == "UNDER" ~ paste("Under", bet_line),
        TRUE                ~ bet_team
      ),
      bookmaker_key  = if ("bookmaker_key" %in% names(.)) bookmaker_key
                       else NA_character_,
      bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
      game_start    = as.POSIXct(NA)
    ) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── Tennis ATP/WTA ───────────────────────────────────────────────────────────
  tennis_value_bets %>%
    mutate(bet_type      = "ML",
           bet_line      = NA_real_,
           bookmaker_key  = if ("bookmaker_key" %in% names(.)) bookmaker_key
                            else NA_character_,
           bookmaker_name = coalesce(BOOK_DISPLAY_NAMES[bookmaker_key], bookmaker_key),
           game_start    = as.POSIXct(NA)) %>%
    select(sport, game_date, game_start, home_team, away_team,
           bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
           bet_line, bookmaker_key, bookmaker_name),

  # ── Challenger ───────────────────────────────────────────────────────────────
  if (nrow(tennis_picks) > 0)
    tennis_picks %>%
      mutate(bet_type  = "ML",
             bet_line  = NA_real_,
             game_start = if ("game_start" %in% names(.)) game_start
                          else as.POSIXct(NA)) %>%
      transmute(sport         = sport_tournament,   # "CHA - Kigali" etc.
                game_date, game_start,
                home_team     = home_player,
                away_team     = away_player,
                bet_type, bet_team, bet_ml, bet_ev, raw_kelly, scaled_kelly,
                bet_line,
                bookmaker_key  = if ("book"             %in% names(.)) book             else NA_character_,
                bookmaker_name = if ("bookmaker_display" %in% names(.)) bookmaker_display else NA_character_)
  else tibble()

) %>%
  filter(!is.na(bet_ml), !is.na(scaled_kelly)) %>%
  mutate(bet_ev_pct = bet_ev * 100)

# ── Cap enforcer ──────────────────────────────────────────────────────────────
# Methodology: uniform scaling across all gate-passing bets.
# Every bet is scaled by the same factor so total risk fits within hard_cap.
# Bets below MIN_BET_DOLLAR are dropped as not practically actionable.
# This preserves the 2-gate philosophy: if a bet passed EV + edge gates,
# bankroll constraints size it down uniformly rather than eliminating it by
# EV rank. Sport-level Kelly multipliers (sector tilts) are a future
# enhancement once sufficient data exists to justify differential weighting.
# Track raw_kelly by sport in paper log for post-hoc sector analysis.
MIN_BET_DOLLAR <- 0.50   # practical minimum stake — scale with bankroll growth

cap_daily_bets <- function(picks_df, bankroll = 1000, cap_pct = 0.10,
                           min_bet = MIN_BET_DOLLAR) {
  if (nrow(picks_df) == 0) {
    cat("ℹ️  cap_daily_bets: no picks to cap.\n")
    return(picks_df)
  }

  hard_cap       <- bankroll * cap_pct
  total_raw_risk <- sum(picks_df$scaled_kelly * bankroll, na.rm = TRUE)

  # Uniform scale factor: shrink all bets proportionally if over cap.
  # If already under cap, sf_cap = 1.0 (no scaling needed).
  sf_cap <- if (total_raw_risk > hard_cap) hard_cap / total_raw_risk else 1.0

  capped <- picks_df %>%
    mutate(
      final_risk = scaled_kelly * bankroll * sf_cap
    ) %>%
    filter(final_risk >= min_bet)

  n_dropped <- nrow(picks_df) - nrow(capped)

  cat(sprintf(
    "CAPPED: %.1f%% risk ($%.2f / $%.0f bankroll) | %d bets | scale: %.4f%s\n",
    sum(capped$final_risk) / bankroll * 100,
    sum(capped$final_risk),
    bankroll,
    nrow(capped),
    sf_cap,
    if (n_dropped > 0) sprintf(" | %d sub-$%.2f dropped", n_dropped, min_bet) else ""
  ))

  return(capped)
}

final_picks <- cap_daily_bets(all_picks_df, bankroll = current_bankroll)

daily_picks_path <- file.path("logs",
                              paste0("daily_picks_", Sys.Date(), ".csv"))

# ── Write clean, human-readable daily picks sheet ────────────────────────────
# Column order and names optimised for quick review and sharing.
# Soccer note: Home/Away reflect actual venue (FotMob/TOA convention).
# Most US books display soccer with away team listed first — opposite of this sheet.
final_picks_clean <- final_picks %>%
  mutate(
    # Game time — convert UTC game_start to ET for display.
    # NOTE: Challenger times are stored as local time (no tz) — with_tz()
    #   misinterprets them. Parked for fix: Challenger needs tz="America/New_York"
    #   on construction, or a sport-aware tz branch here.
    # NOTE: TOA returns midnight UTC for NCAAB/NBA tournament games without
    #   confirmed tip times. These correctly display as 08:00 PM ET but are
    #   not meaningful. Parked for fix: detect midnight-UTC sentinel and show
    #   "TBD" instead; also explore ESPN API as a fallback for confirmed times.
    `Time (ET)` = if_else(
      !is.na(game_start),
      format(with_tz(game_start, "America/New_York"), "%I:%M %p"),
      "TBD"
    ),
    # Normalise Bet Type labels
    `Bet Type` = case_when(
      bet_type == "ML"                  ~ "ML",
      bet_type == "SPREAD"              ~ "Spread",
      bet_type %in% c("OVER", "UNDER")  ~ "Total",
      TRUE                              ~ bet_type
    ),
    # Pick: team + line for spreads; "Over/Under X.X" for totals; team for ML
    Pick = case_when(
      bet_type == "SPREAD" & !is.na(bet_line) ~
        paste0(bet_team, " ", sprintf("%+.1f", bet_line)),
      TRUE ~ bet_team
    ),
    # Bookmaker display name — sourced from API's own bookmaker field via
    # bookmaker_name column in all_picks_df; fall back to raw key if missing
    Book = coalesce(bookmaker_name, bookmaker_key)
  ) %>%
  select(
    Sport        = sport,
    Date         = game_date,
    `Time (ET)`,
    Home         = home_team,
    Away         = away_team,
    `Bet Type`,
    Pick,
    Odds         = bet_ml,
    Book,
    EV           = bet_ev_pct,
    Kelly        = scaled_kelly,
    `Risk $`     = final_risk
  ) %>%
  mutate(
    Date     = format(Date, "%m/%d/%y"),
    Odds     = round(Odds, 2),
    EV       = round(EV, 1),
    Kelly    = round(Kelly, 4),
    `Risk $` = round(`Risk $`, 2)
  ) %>%
  arrange(Date, `Time (ET)`, Sport)

write_csv(final_picks_clean, daily_picks_path)
cat(sprintf("✅ Daily picks written: %d bets → %s\n",
            nrow(final_picks_clean), daily_picks_path))

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

# ── Write logs — only bets that survived cap_daily_bets() ────────────────────
# final_picks has the capped set (slim columns). Rejoin to full-column source
# dataframes using sport/date/teams/bet_type/bet_team as the key so that
# position_id, lifecycle fields, and edge columns are preserved in the logs.
# This ensures bet counts match daily_picks, not the raw candidate lists.

capped_ml_key <- final_picks %>%
  filter(bet_type == "ML", sport %in% c("NBA", "NCAAB", "NHL")) %>%
  select(sport, game_date, home_team, away_team, bet_team)

capped_st_key <- final_picks %>%
  filter(bet_type %in% c("SPREAD", "OVER", "UNDER")) %>%
  select(sport, game_date, home_team, away_team, bet_type, bet_team)

value_best_capped <- value_best %>%
  semi_join(capped_ml_key,
            by = c("sport", "game_date", "home_team", "away_team", "bet_team"))

spread_total_best_capped <- spread_total_best %>%
  mutate(bet_team = case_when(
    bet_type == "OVER"  ~ paste("Over",  bet_line),
    bet_type == "UNDER" ~ paste("Under", bet_line),
    TRUE                ~ bet_team
  )) %>%
  semi_join(capped_st_key,
            by = c("sport", "game_date", "home_team", "away_team",
                   "bet_type", "bet_team"))

cat(sprintf("Combined picks: %d ML + %d ST | Total raw kelly: %.4f | Scale factor: %.4f | Cap triggered: %s\n",
            nrow(value_best_capped), nrow(spread_total_best_capped),
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

write_bet_log(value_best_capped)
write_spread_total_log(spread_total_best_capped)

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

# ---- Tennis bet log ----
tennis_log_path <- file.path("logs", paste0("tennis_bet_log_", Sys.Date(), ".csv"))

tennis_bet_log_new <- tennis_value_bets %>%
  mutate(log_date = Sys.Date()) %>%
  select(sport, log_date, game_date, open_time,
         home_team, away_team,
         value_side, bet_team, bet_ml,
         home_elo, away_elo, elo_diff, model_home_prob,
         home_ev, away_ev, bet_ev,
         raw_kelly, scaled_kelly,
         position_id, status, result, pnl) %>%
  mutate(result = as.character(result))

write_csv(tennis_bet_log_new, tennis_log_path)
cat("\nTennis bet log written:", tennis_log_path, "\n")
cat(nrow(tennis_bet_log_new), "tennis value bets logged\n")

# ---- Challenger bet log ----
if (nrow(tennis_picks) > 0) {
  challenger_log_path <- file.path("logs",
                                   paste0("challenger_picks_", Sys.Date(), ".csv"))
  write_csv(tennis_picks, challenger_log_path)
  cat("\nChallenger bet log written:", challenger_log_path, "\n")
  cat(nrow(tennis_picks), "challenger value bets logged\n")

  # NOTE: elite_challenger_bets removed — those picks are already in challenger_picks.
  # Filter on alignment == "✅ Elite" if you want an elite-only view.
}

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

# ---- Combine all results ----
all_results <- bind_rows(
  nba_results   %>% filter(completed == TRUE) %>% mutate(sport = "NBA"),
  nhl_results   %>% filter(completed == TRUE) %>% mutate(sport = "NHL"),
  ncaab_results %>% filter(completed == TRUE) %>% mutate(sport = "NCAAB")
) %>%
  mutate(winner = ifelse(home_score > away_score, home_team, away_team))

# ---- Load yesterday's bet log ----
# Handles both old format (has close_price) and new format (doesn't)
# Guard: log may not exist if yesterday was the first run day or logs were archived.
if (!file.exists(log_path)) {
  cat(sprintf("ℹ️  No bet log found for %s (archived or first run) — skipping ML settler.\n",
              format(yesterday)))
  bet_log <- tibble()   # empty tibble — scorer block below is no-op on 0 rows
} else {
  bet_log <- read_csv(log_path,
                      col_types = cols(
                        result    = col_character(),
                        pnl       = col_double(),
                        game_date = col_date(),
                        .default  = col_guess()
                      ),
                      show_col_types = FALSE)
}

# ---- Score settled bets ----
soccer_settled_today <- map_dfr(soccer_log_files,
                                ~ settle_soccer_log(.x, soccer_results_yesterday))

cat(sprintf("\n=== SOCCER SETTLER ===\n"))
cat("Files scanned:", length(soccer_log_files), "\n")
cat("Newly settled:", nrow(soccer_settled_today), "bets\n")

if (nrow(soccer_settled_today) > 0) {
  print(soccer_settled_today %>%
          select(sport, game_date, home_team, away_team,
                 value_side, bet_team, bet_ml, result, pnl))
}

cat("\nSoccer results fetched:", nrow(soccer_results_yesterday), "completed matches\n")
print(soccer_results_yesterday %>%
        filter(league == "EPL") %>%
        select(league, game_date, home_team, away_team,
               home_score, away_score, match_result))

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

# ============================================================
# TENNIS SETTLER — ATP/WTA main tour
# ============================================================

# ── Results fetcher: TOA scores endpoint ─────────────────────────────────────
# TOA /scores returns a 'scores' list-column. Each element is either:
#   (a) a data frame with columns {name, score}  — one row per team, or
#   (b) a list of named lists: list(list(name=..., score=...), ...)
# There are NO flat home_score / away_score columns.
#
# Tennis scoring: TOA reports sets won (e.g. "2", "1"). Winner = most sets.
#
# Helper: extract winner from one row's scores element
extract_tennis_winner <- function(scores_elem, home_team, away_team) {
  tryCatch({
    # Normalise to data frame regardless of list vs data.frame format
    sc <- if (is.data.frame(scores_elem)) {
      scores_elem
    } else if (is.list(scores_elem) && length(scores_elem) >= 2) {
      bind_rows(lapply(scores_elem, function(x) as.data.frame(as.list(x),
                                                               stringsAsFactors = FALSE)))
    } else {
      return(NA_character_)
    }

    if (!"name" %in% names(sc) || !"score" %in% names(sc)) return(NA_character_)
    if (nrow(sc) < 2) return(NA_character_)

    sc <- sc %>% mutate(score_n = suppressWarnings(as.numeric(as.character(score))))

    # Match rows to home/away by name (exact → partial → row order fallback)
    find_row <- function(team) {
      r <- sc %>% filter(name == team) %>% slice(1)
      if (nrow(r) > 0) return(r)
      r <- sc %>% filter(str_detect(team, fixed(name)) |
                           str_detect(name, fixed(team))) %>% slice(1)
      r
    }

    home_row <- find_row(home_team)
    away_row <- find_row(away_team)

    if (nrow(home_row) == 0) home_row <- sc %>% slice(1)
    if (nrow(away_row) == 0) away_row <- sc %>% slice(2)

    hs <- home_row$score_n[1]
    as_ <- away_row$score_n[1]

    if (is.na(hs) || is.na(as_)) return(NA_character_)
    if_else(hs > as_, home_team, away_team)
  }, error = function(e) NA_character_)
}

fetch_tennis_results <- function(target_date = Sys.Date() - 1) {

  tennis_keys_live <- multi_odds_filtered %>%
    filter(grepl("^tennis_", sport_key)) %>%
    distinct(sport_key) %>%
    pull(sport_key)

  if (length(tennis_keys_live) == 0) {
    cat("Tennis settler: no tennis sport keys found in multi_odds_filtered\n")
    return(tibble())
  }

  map_dfr(tennis_keys_live, function(sk) {
    tryCatch({
      raw <- toa_sports_scores(
        sport_key   = sk,
        days_from   = 1,
        date_format = "iso"
      )
      if (is.null(raw) || nrow(raw) == 0) return(tibble())

      raw <- raw %>%
        filter(isTRUE(completed)) %>%
        mutate(game_date = as.Date(substr(commence_time, 1, 10))) %>%
        filter(game_date == target_date)

      if (nrow(raw) == 0) return(tibble())

      # ── Row-wise extraction using index — no column enumeration needed ──
      map_dfr(seq_len(nrow(raw)), function(i) {
        ht     <- raw$home_team[i]
        at     <- raw$away_team[i]
        sc_raw <- raw$scores[[i]]   # the nested element for this row

        winner <- extract_tennis_winner(sc_raw, ht, at)
        if (is.na(winner)) return(tibble())

        tibble(
          sport_key = sk,
          game_date = raw$game_date[i],
          home_team = ht,
          away_team = at,
          winner    = winner
        )
      })

    }, error = function(e) {
      message("Tennis scores fetch failed (", sk, "): ", e$message)
      tibble()
    })
  })
}

# ── Settler function — mirrors settle_soccer_log exactly ─────────────────────
settle_tennis_log <- function(log_path, results_df) {
  if (!file.exists(log_path)) return(invisible(NULL))

  if (is.null(results_df) || nrow(results_df) == 0) {
    cat(sprintf("⏭️  Tennis settler: no results — skipping %s\n", basename(log_path)))
    return(invisible(NULL))
  }

  log <- read_csv(log_path,
                  col_types = cols(result       = col_character(),
                                   pnl          = col_double(),
                                   game_date    = col_date(),
                                   bet_ml       = col_double(),
                                   scaled_kelly = col_double(),
                                   .default     = col_guess()),
                  show_col_types = FALSE)

  unsettled <- log %>% filter(is.na(result) | result == "NA")
  if (nrow(unsettled) == 0) {
    cat(sprintf("ℹ️  Tennis settler: all bets already settled in %s\n", basename(log_path)))
    return(invisible(NULL))
  }

  scored <- unsettled %>%
    left_join(
      results_df %>% select(game_date, home_team, away_team, winner),
      by = c("game_date", "home_team", "away_team")
    ) %>%
    mutate(
      result = case_when(
        is.na(winner)              ~ NA_character_,
        bet_team == winner         ~ "W",
        !is.na(winner)             ~ "L",
        TRUE                       ~ NA_character_
      ),
      pnl = case_when(
        result == "W" ~ (bet_ml - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ NA_real_
      )
    ) %>%
    select(-winner)

  updated_log <- bind_rows(
    log %>% filter(!is.na(result) & result != "NA"),
    scored
  ) %>% arrange(game_date, home_team)

  newly_settled <- scored %>% filter(!is.na(result))
  if (nrow(newly_settled) > 0) {
    cat(sprintf("Settled %d tennis bets in %s\n",
                nrow(newly_settled), basename(log_path)))
    print(newly_settled %>%
            select(sport, game_date, home_team, away_team,
                   bet_team, bet_ml, result, pnl))
    write_csv(updated_log, log_path)
  } else {
    cat(sprintf("ℹ️  Tennis settler: no new matches completed for %s\n", basename(log_path)))
  }

  invisible(newly_settled)
}

# ── Run tennis settler ────────────────────────────────────────────────────────
tennis_results_yesterday <- fetch_tennis_results(target_date = yesterday)

tennis_log_files <- list.files("logs",
                               pattern   = "^tennis_bet_log_.*\\.csv$",
                               full.names = TRUE)

tennis_settled_today <- map_dfr(tennis_log_files,
                                ~ settle_tennis_log(.x, tennis_results_yesterday))

cat(sprintf("\n=== TENNIS SETTLER ===\n"))
cat("Files scanned:", length(tennis_log_files), "\n")
cat("Newly settled:", nrow(tennis_settled_today), "bets\n")

# ── Tennis PnL for paper trading (by game_date) ───────────────────────────────
tennis_pnl_by_date <- if (nrow(tennis_settled_today) > 0) {
  tennis_settled_today %>%
    filter(!is.na(result)) %>%
    group_by(game_date) %>%
    summarise(
      tennis_pnl    = sum(pnl,          na.rm = TRUE),
      tennis_wins   = sum(result == "W"),
      tennis_losses = sum(result == "L"),
      .groups = "drop"
    )
} else {
  tibble(game_date    = as.Date(character()),
         tennis_pnl   = numeric(),
         tennis_wins  = integer(),
         tennis_losses = integer())
}

# ============================================================
# CHALLENGER SETTLER — ATP Challenger tour
# ============================================================

# ── Results fetcher: ESPN tennis scoreboard ───────────────────────────────────
# ESPN covers major Challenger events under the "ten" sport slug.
# Name cleaning: strips seeding "(1)", qualifier "(Q)", wildcard "(WC)",
# alternate "(Alt)", and nationality "(XXX)" from TOA/spreadsheet names.
clean_tennis_name <- function(x) {
  x %>%
    str_remove("^\\([^)]*\\)\\s*") %>%   # remove leading (seed/Q/WC/Alt/LL)
    str_remove("\\s*\\([A-Z]{2,3}\\)$") %>%  # remove trailing (NAT)
    str_squish()
}

fetch_challenger_results <- function(target_date = Sys.Date() - 1) {
  # ESPN has no generic "ten" Challenger endpoint — must hit "atp" and "wta"
  # slugs separately. Both are tried; results are combined.
  date_str <- format(target_date, "%Y%m%d")
  slugs    <- c("atp", "wta")

  parse_espn_tennis <- function(raw, slug) {
    if (is.null(raw) || !is.data.frame(raw$events) || nrow(raw$events) == 0)
      return(tibble())

    map_dfr(seq_len(nrow(raw$events)), function(i) {
      tryCatch({
        comp      <- raw$events$competitions[[i]]
        stype     <- comp$status$type
        completed <- isTRUE(stype$completed) ||
                     identical(stype$name, "STATUS_FINAL") ||
                     identical(stype$description, "Final")
        if (!completed) return(tibble())

        competitors <- comp$competitors[[1]]

        # ESPN tennis: winner flagged by winner == TRUE column
        if ("winner" %in% names(competitors)) {
          winner_row <- competitors[isTRUE(competitors$winner), ]
          loser_row  <- competitors[!isTRUE(competitors$winner), ]
        } else {
          # Fallback: derive winner from linescores if available
          return(tibble())
        }
        if (nrow(winner_row) == 0) return(tibble())

        # Name extraction — athlete or team depending on ESPN response shape
        get_name <- function(row) {
          n <- tryCatch(row$athlete$displayName, error = function(e) NULL)
          if (!is.null(n) && length(n) > 0 && !is.na(n[1])) return(n[1])
          n <- tryCatch(row$team$displayName,   error = function(e) NULL)
          if (!is.null(n) && length(n) > 0 && !is.na(n[1])) return(n[1])
          NA_character_
        }

        w_name <- get_name(winner_row)
        l_name <- get_name(loser_row)
        if (is.na(w_name)) return(tibble())

        tibble(
          game_date    = as.Date(substr(raw$events$date[i], 1, 10)),
          winner_raw   = w_name,
          loser_raw    = l_name,
          winner_clean = clean_tennis_name(w_name),
          loser_clean  = clean_tennis_name(l_name)
        )
      }, error = function(e) {
        message("ESPN Challenger parse error (", slug, " event ", i, "): ", e$message)
        tibble()
      })
    })
  }

  results <- map_dfr(slugs, function(slug) {
    url <- paste0(
      "http://site.api.espn.com/apis/site/v2/sports/tennis/",
      slug, "/scoreboard?dates=", date_str
    )
    raw <- tryCatch(fromJSON(url), error = function(e) {
      message("ESPN tennis fetch failed (", slug, "): ", e$message)
      NULL
    })
    parse_espn_tennis(raw, slug)
  })

  if (nrow(results) == 0) {
    cat("No ESPN tennis results for", format(target_date), "\n")
    return(tibble())
  }

  # Deduplicate — same match can appear under both slugs
  results %>%
    distinct(game_date, winner_clean, loser_clean, .keep_all = TRUE)
}

# ── Challenger settler ────────────────────────────────────────────────────────
# Joins on cleaned names (seedings/nationalities stripped before matching).
settle_challenger_log <- function(log_path, results_df) {
  if (!file.exists(log_path)) return(invisible(NULL))

  if (is.null(results_df) || nrow(results_df) == 0) {
    cat(sprintf("⏭️  Challenger settler: no results — skipping %s\n", basename(log_path)))
    return(invisible(NULL))
  }

  log <- read_csv(log_path,
                  col_types = cols(result       = col_character(),
                                   pnl          = col_double(),
                                   game_date    = col_date(),
                                   bet_ml       = col_double(),
                                   scaled_kelly = col_double(),
                                   .default     = col_guess()),
                  show_col_types = FALSE)

  unsettled <- log %>% filter(is.na(result) | result == "NA")
  if (nrow(unsettled) == 0) {
    cat(sprintf("ℹ️  Challenger settler: all bets settled in %s\n", basename(log_path)))
    return(invisible(NULL))
  }

  # Clean names for join — strip seedings/nationalities
  unsettled_clean <- unsettled %>%
    mutate(
      home_clean = clean_tennis_name(home_player),
      away_clean = clean_tennis_name(away_player),
      bet_clean  = clean_tennis_name(bet_team)
    )

  scored <- unsettled_clean %>%
    left_join(
      results_df %>% select(game_date, winner_clean, loser_clean),
      by = "game_date"
    ) %>%
    # Match: bet's cleaned players appear in winner/loser
    filter(
      (home_clean == winner_clean & away_clean == loser_clean) |
      (home_clean == loser_clean  & away_clean == winner_clean)
    ) %>%
    # One row per bet after join
    group_by(position_id) %>%
    slice(1) %>%
    ungroup() %>%
    mutate(
      result = case_when(
        bet_clean == winner_clean ~ "W",
        bet_clean == loser_clean  ~ "L",
        TRUE                      ~ NA_character_
      ),
      pnl = case_when(
        result == "W" ~ (bet_ml - 1) * scaled_kelly,
        result == "L" ~ -scaled_kelly,
        TRUE          ~ NA_real_
      )
    ) %>%
    select(-home_clean, -away_clean, -bet_clean, -winner_clean, -loser_clean)

  # Merge settled rows back; preserve any already-settled rows
  all_position_ids_scored <- scored$position_id
  updated_log <- bind_rows(
    log %>% filter(!is.na(result) & result != "NA"),
    # unsettled rows: replace scored ones, keep unmatched as-is (still NA)
    unsettled %>%
      filter(!position_id %in% all_position_ids_scored),
    scored
  ) %>% arrange(game_date, home_player)

  newly_settled <- scored %>% filter(!is.na(result))
  if (nrow(newly_settled) > 0) {
    cat(sprintf("Settled %d challenger bets in %s\n",
                nrow(newly_settled), basename(log_path)))
    print(newly_settled %>%
            select(sport, sport_tournament, game_date,
                   bet_team, bet_ml, result, pnl))
    write_csv(updated_log, log_path)
  } else {
    cat(sprintf("ℹ️  Challenger settler: no matches completed for %s\n", basename(log_path)))
  }

  invisible(newly_settled)
}

# ── Run challenger settler ────────────────────────────────────────────────────
challenger_results_yesterday <- fetch_challenger_results(target_date = yesterday)

challenger_log_files <- list.files("logs",
                                   pattern   = "^challenger_picks_.*\\.csv$",
                                   full.names = TRUE)

challenger_settled_today <- map_dfr(challenger_log_files,
                                    ~ settle_challenger_log(.x, challenger_results_yesterday))

cat(sprintf("\n=== CHALLENGER SETTLER ===\n"))
cat("Files scanned:", length(challenger_log_files), "\n")
cat("Newly settled:", nrow(challenger_settled_today), "bets\n")

# ── Challenger PnL for paper trading (by game_date) ───────────────────────────
challenger_pnl_by_date <- if (nrow(challenger_settled_today) > 0) {
  challenger_settled_today %>%
    filter(!is.na(result)) %>%
    group_by(game_date) %>%
    summarise(
      challenger_pnl    = sum(pnl,          na.rm = TRUE),
      challenger_wins   = sum(result == "W"),
      challenger_losses = sum(result == "L"),
      .groups = "drop"
    )
} else {
  tibble(game_date        = as.Date(character()),
         challenger_pnl   = numeric(),
         challenger_wins  = integer(),
         challenger_losses = integer())
}


bet_log_scored <- if (nrow(bet_log) == 0) {
  cat("ℹ️  ML settler: no yesterday log to score.\n")
  tibble()
} else {
  bet_log %>%
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
}

# ---- Preview and save ----
if (nrow(bet_log_scored) > 0) {
  cat("\nScored bets:\n")
  print(bet_log_scored %>%
          filter(!is.na(result)) %>%
          select(sport, game_date, home_team, away_team,
                 bet_team, bet_ml, scaled_kelly, result, pnl))
  
  write_csv(bet_log_scored, log_path)
  cat("\nBet log updated:", log_path, "\n")
  cat("Total settled PnL:", round(sum(bet_log_scored$pnl, na.rm = TRUE), 6), "\n")
  cat("Unsettled picks remaining:", sum(is.na(bet_log_scored$result)), "\n")
}

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

STARTING_BANKROLL <- 1000.00  # Reset 2026-03-13 (prior logs archived — see performance_review_2026-03-12.md)
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
# ── Helper: load daily_picks and extract correct post-cap kelly + risk ─────────
# daily_picks_YYYY-MM-DD.csv is the single source of truth for what was
# actually staked. Sport logs carry pre-cap scaled_kelly values which overstate
# risk. This helper returns a joinable tibble keyed on bet identity.
load_daily_picks_kelly <- function(picks_path) {
  if (is.null(picks_path) || !file.exists(picks_path)) return(NULL)
  read_csv(picks_path,
           col_types = cols(
             Home       = col_character(),
             Away       = col_character(),
             Pick       = col_character(),
             Odds       = col_double(),
             Kelly      = col_double(),
             `Risk $`   = col_double(),
             .default   = col_guess()
           ),
           show_col_types = FALSE) %>%
    transmute(
      home_team    = Home,
      away_team    = Away,
      bet_team     = Pick,
      bet_ml       = Odds,
      capped_kelly = Kelly,
      risk_dollar  = `Risk $`
    )
}

settle_paper_day <- function(ml_log_path, bankroll_at_open, st_log_path = NULL,
                             log_date_override          = NULL,
                             daily_picks_path           = NULL,
                             soccer_pnl_by_date_arg     = NULL,
                             tennis_pnl_by_date_arg     = NULL,
                             challenger_pnl_by_date_arg = NULL) {
  
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

  # ── Patch scaled_kelly + dollar amounts from daily_picks (post-cap) ─────────
  # Sport logs carry pre-cap scaled_kelly which overstates stakes ~3x.
  # Join on bet identity to replace with the actual capped values.
  picks_kelly <- load_daily_picks_kelly(daily_picks_path)

  if (!is.null(picks_kelly)) {
    all_settled <- all_settled %>%
      left_join(
        picks_kelly %>% select(home_team, away_team, bet_team, capped_kelly, risk_dollar),
        by = c("home_team", "away_team", "bet_team")
      ) %>%
      mutate(
        scaled_kelly = coalesce(capped_kelly, scaled_kelly),
        dollar_stake = coalesce(risk_dollar,  dollar_stake),
        dollar_pnl   = case_when(
          result == "W" ~ (bet_ml - 1) * scaled_kelly * bankroll_at_open,
          result == "L" ~ -scaled_kelly * bankroll_at_open,
          TRUE          ~ dollar_pnl
        )
      ) %>%
      select(-capped_kelly, -risk_dollar)
  }
  
  # ── Bug #2 guard: log_date may have multiple values if log spans multiple days.
  # Always take the first value and warn so the caller knows to use log_date_override.
  if (is.null(log_date_override)) {
    raw_dates <- unique(ml_log$log_date)
    if (length(raw_dates) > 1) {
      warning(sprintf(
        "settle_paper_day: ml_log contains %d distinct log_date values (%s). ",
        length(raw_dates),
        paste(format(as.Date(raw_dates)), collapse = ", ")
      ), "Using the first. Pass log_date_override to be explicit.")
    }
    resolved_date <- as.Date(raw_dates[1])
  } else {
    resolved_date <- as.Date(log_date_override)
  }

  # ---- NEW: Soccer PnL for this date ----
  soccer_day_pnl_kelly  <- 0
  soccer_day_wins       <- 0L
  soccer_day_losses     <- 0L
  
  if (!is.null(soccer_pnl_by_date_arg) && nrow(soccer_pnl_by_date_arg) > 0) {
    soccer_row <- soccer_pnl_by_date_arg %>% filter(game_date == resolved_date)
    if (nrow(soccer_row) > 0) {
      soccer_day_pnl_kelly <- soccer_row$soccer_pnl[1]
      soccer_day_wins      <- soccer_row$soccer_wins[1]
      soccer_day_losses    <- soccer_row$soccer_losses[1]
    }
  }
  
  soccer_day_pnl_dollar <- soccer_day_pnl_kelly * bankroll_at_open

  # ── Tennis PnL for this date ──────────────────────────────────────────────
  tennis_day_pnl_kelly  <- 0
  tennis_day_wins       <- 0L
  tennis_day_losses     <- 0L

  if (!is.null(tennis_pnl_by_date_arg) && nrow(tennis_pnl_by_date_arg) > 0) {
    tennis_row <- tennis_pnl_by_date_arg %>% filter(game_date == resolved_date)
    if (nrow(tennis_row) > 0) {
      tennis_day_pnl_kelly <- tennis_row$tennis_pnl[1]
      tennis_day_wins      <- tennis_row$tennis_wins[1]
      tennis_day_losses    <- tennis_row$tennis_losses[1]
    }
  }

  tennis_day_pnl_dollar <- tennis_day_pnl_kelly * bankroll_at_open

  # ── Challenger PnL for this date ──────────────────────────────────────────
  challenger_day_pnl_kelly  <- 0
  challenger_day_wins       <- 0L
  challenger_day_losses     <- 0L

  if (!is.null(challenger_pnl_by_date_arg) && nrow(challenger_pnl_by_date_arg) > 0) {
    chall_row <- challenger_pnl_by_date_arg %>% filter(game_date == resolved_date)
    if (nrow(chall_row) > 0) {
      challenger_day_pnl_kelly <- chall_row$challenger_pnl[1]
      challenger_day_wins      <- chall_row$challenger_wins[1]
      challenger_day_losses    <- chall_row$challenger_losses[1]
    }
  }

  challenger_day_pnl_dollar <- challenger_day_pnl_kelly * bankroll_at_open

  # ── Combined non-core PnL ─────────────────────────────────────────────────
  extra_pnl_kelly  <- soccer_day_pnl_kelly  + tennis_day_pnl_kelly  + challenger_day_pnl_kelly
  extra_pnl_dollar <- soccer_day_pnl_dollar + tennis_day_pnl_dollar + challenger_day_pnl_dollar
  extra_wins       <- soccer_day_wins  + tennis_day_wins  + challenger_day_wins
  extra_losses     <- soccer_day_losses + tennis_day_losses + challenger_day_losses

  tibble(
    date = resolved_date,
    starting_bankroll  = bankroll_at_open,
    total_risked       = if (!is.null(picks_kelly)) {
                           sum(picks_kelly$risk_dollar, na.rm = TRUE)
                         } else {
                           sum(all_settled$dollar_stake, na.rm = TRUE)
                         },
    settled_pnl_kelly  = sum(all_settled$pnl,        na.rm = TRUE) + extra_pnl_kelly,
    settled_pnl_dollar = sum(all_settled$dollar_pnl, na.rm = TRUE) + extra_pnl_dollar,
    ending_bankroll    = round(bankroll_at_open +
                                 sum(all_settled$dollar_pnl, na.rm = TRUE) +
                                 extra_pnl_dollar, 2),
    daily_roi          = (sum(all_settled$dollar_pnl, na.rm = TRUE) + extra_pnl_dollar) /
      bankroll_at_open,
    cumulative_roi     = NA_real_,
    wins               = sum(all_settled$result == "W") + extra_wins,
    losses             = sum(all_settled$result == "L") + extra_losses,
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


# ---- Backfill any missing historical days (Bug #14 fix) ----
# Derived dynamically from bet_log_*.csv files in the logs/ directory.
# No longer needs hand-editing when a new day is added.
log_files_on_disk <- list.files(
  file.path(getwd(), "logs"),
  pattern    = "^bet_log_\\d{4}-\\d{2}-\\d{2}\\.csv$",
  full.names = FALSE
)
backfill_dates <- sort(as.Date(
  sub("bet_log_(\\d{4}-\\d{2}-\\d{2})\\.csv", "\\1", log_files_on_disk)
))
# Exclude today (not yet settled) and yesterday (handled separately below)
backfill_dates <- backfill_dates[backfill_dates < yesterday]
cat(sprintf("Backfill candidates: %d dates (%s to %s)\n",
            length(backfill_dates),
            if (length(backfill_dates)) format(min(backfill_dates)) else "—",
            if (length(backfill_dates)) format(max(backfill_dates)) else "—"))

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
                               st_log_path                = bf_st_path,
                               log_date_override          = bf_date,
                               daily_picks_path           = file.path(getwd(), "logs",
                                                            paste0("daily_picks_", bf_date, ".csv")),
                               soccer_pnl_by_date_arg     = soccer_pnl_by_date,
                               tennis_pnl_by_date_arg     = tennis_pnl_by_date,
                               challenger_pnl_by_date_arg = challenger_pnl_by_date)
    
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
  if (!file.exists(log_path)) {
    cat(sprintf("ℹ️  No yesterday log (%s) — paper log stays at $%.2f until first results settle.\n",
                format(yesterday), current_br))
  } else {
    yesterday_bankroll <- if (nrow(paper_log) == 0) {
      STARTING_BANKROLL
    } else {
      tail(paper_log$ending_bankroll, 1)
    }
    
    yesterday_row <- settle_paper_day(log_path, yesterday_bankroll,
                                      st_log_path                = spread_total_log_path,
                                      log_date_override          = yesterday,
                                      daily_picks_path           = file.path(getwd(), "logs",
                                                                   paste0("daily_picks_", yesterday, ".csv")),
                                      soccer_pnl_by_date_arg     = soccer_pnl_by_date,
                                      tennis_pnl_by_date_arg     = tennis_pnl_by_date,
                                      challenger_pnl_by_date_arg = challenger_pnl_by_date)
    
    if (!is.null(yesterday_row)) {
      paper_log <- paper_log %>%
        filter(date != yesterday) %>%
        bind_rows(yesterday_row) %>%
        arrange(date)
      cat("Yesterday (", format(yesterday), ") paper log updated.\n")
    }
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
current_br   <- if (nrow(paper_log) > 0) tail(paper_log$ending_bankroll, 1) else STARTING_BANKROLL
current_pnl  <- current_br - STARTING_BANKROLL
current_roi  <- if (nrow(paper_log) > 0) tail(paper_log$cumulative_roi, 1) * 100 else 0

cat("\n========================================\n")
cat("       PAPER TRADING DASHBOARD\n")
cat("========================================\n")
cat("Starting bankroll:  $", formatC(STARTING_BANKROLL, format="f", digits=2), "\n")
cat("Current bankroll:   $", formatC(current_br,        format="f", digits=2), "\n")
cat("Total P&L:          $", formatC(current_pnl,       format="f", digits=2), "\n")
cat("Cumulative ROI:     ",  round(current_roi, 2), "%\n")
cat("Overall record:     ",  sum(paper_log$wins, na.rm=TRUE), "W -",
                             sum(paper_log$losses, na.rm=TRUE), "L\n")
cat("Days tracked:       ",  nrow(paper_log), "\n")
if (nrow(paper_log) == 0)
  cat("  (No settled days yet — bets logged, awaiting first results)\n")
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


# ============================================================
# TOOLS — run analytical modules after daily engine completes
# ============================================================
# Vig monitor: captures bookmaker overround snapshot at pick-generation
# time. Running here ensures the vig is measured on the same odds feed
# that generated today's picks — critical for time-of-day trend analysis.
# Comment out to skip on any given run.
if (file.exists("tools/vig_monitor.R")) {
  source("tools/vig_monitor.R")
} else {
  message("ℹ️  tools/vig_monitor.R not found — skipping. ",
          "Place tools/ folder in: ", getwd())
}

# TOA quota tracker: log today's requests and print usage vs. tier limit.
# n_requests = number of sport keys fetched (one API request per key).
if (file.exists("tools/toa_quota_monitor.R")) {
  source("tools/toa_quota_monitor.R")
  if (FETCH_ODDS) {
    toa_log_request(
      call_type  = "odds_fetch",
      n_requests = length(sports),
      sports     = sports,
      notes      = "daily run"
    )
  }
  toa_quota_report()
  toa_poll_budget(n_sports = length(sports))
} else {
  message("ℹ️  tools/toa_quota_monitor.R not found — skipping quota tracking.")
}

# ============================================================
# JSON EXPORTS — ArcVest dashboard data contracts
# ============================================================
# Writes three JSON files to docs/data/ for the static HTML dashboard.
# docs/ is committed to GitHub; GitHub Pages serves arcvest.io from it.
# The dashboard reads these files directly — no server required.
# Only runs if jsonlite is available (already loaded via library block above).

json_dir <- file.path(getwd(), "docs", "data")
if (!dir.exists(json_dir)) dir.create(json_dir, recursive = TRUE)

# ── 1. daily_picks.json — today's capped picks ───────────────────────────────
tryCatch({
  write(toJSON(final_picks_clean, auto_unbox = TRUE, na = "null", digits = 4),
        file.path(json_dir, "daily_picks.json"))
  cat(sprintf("✅ JSON: daily_picks.json written (%d picks)\n",
              nrow(final_picks_clean)))
}, error = function(e) message("⚠️  daily_picks.json write failed: ", e$message))

# ── 2. paper_log.json — full paper trading history ───────────────────────────
tryCatch({
  paper_export <- paper_log %>%
    mutate(date = format(date, "%Y-%m-%d"))
  write(toJSON(paper_export, auto_unbox = TRUE, na = "null", digits = 4),
        file.path(json_dir, "paper_log.json"))
  cat(sprintf("✅ JSON: paper_log.json written (%d days)\n", nrow(paper_log)))
}, error = function(e) message("⚠️  paper_log.json write failed: ", e$message))

# ── 3. summary.json — dashboard KPIs and record by sport ─────────────────────
tryCatch({
  # Build W/L/ROI record by sport from all settled bet logs
  all_settled_bets <- tryCatch({
    ml_files <- list.files(file.path(getwd(), "logs"),
                           pattern = "^bet_log_.*\\.csv$", full.names = TRUE)
    st_files <- list.files(file.path(getwd(), "logs"),
                           pattern = "^spread_total_log_.*\\.csv$", full.names = TRUE)
    bind_rows(
      map_dfr(ml_files, ~ read_csv(.x, col_types = cols(.default = col_guess()),
                                   show_col_types = FALSE)),
      map_dfr(st_files, ~ read_csv(.x, col_types = cols(.default = col_guess()),
                                   show_col_types = FALSE))
    ) %>% filter(result %in% c("W", "L"))
  }, error = function(e) tibble())

  record_by_sport <- if (nrow(all_settled_bets) > 0) {
    recs <- all_settled_bets %>%
      group_by(sport) %>%
      summarise(
        wins   = sum(result == "W"),
        losses = sum(result == "L"),
        roi    = round(sum(pnl, na.rm = TRUE) /
                       pmax(sum(scaled_kelly, na.rm = TRUE), 0.0001), 4),
        .groups = "drop"
      ) %>%
      arrange(desc(wins + losses))
    setNames(
      lapply(seq_len(nrow(recs)), function(i)
        list(wins = recs$wins[i], losses = recs$losses[i], roi = recs$roi[i])),
      recs$sport
    )
  } else list()

  summary_export <- list(
    starting_bankroll = STARTING_BANKROLL,
    current_bankroll  = round(current_br, 2),
    today_risk        = round(sum(final_picks_clean$`Risk $`, na.rm = TRUE), 2),
    last_run          = format(Sys.time(), "%Y-%m-%d %H:%M"),
    record_by_sport   = record_by_sport
  )

  write(toJSON(summary_export, auto_unbox = TRUE, na = "null", digits = 4),
        file.path(json_dir, "summary.json"))
  cat(sprintf("✅ JSON: summary.json written (%d sports in record)\n",
              length(record_by_sport)))
}, error = function(e) message("⚠️  summary.json write failed: ", e$message))

# ── 4. Inject data inline into arcvest_dashboard.html (local file:// support) ──
# Browsers block fetch() on file:// URLs so the dashboard cannot load JSON
# when opened locally. This writes the three datasets as JS variables directly
# into the HTML. GitHub Pages uses fetch() automatically; local use gets the
# inline data. Both paths work without any server.
tryCatch({
  html_path <- file.path(getwd(), "docs", "index.html")
  if (!file.exists(html_path)) html_path <- file.path(getwd(), "arcvest_dashboard.html")
  if (file.exists(html_path)) {
    html <- readLines(html_path, encoding = "UTF-8", warn = FALSE)
    picks_json   <- toJSON(final_picks_clean, auto_unbox = TRUE, na = "null", digits = 4)
    paper_json   <- toJSON(paper_export,       auto_unbox = TRUE, na = "null", digits = 4)
    summary_json <- toJSON(summary_export,     auto_unbox = TRUE, na = "null", digits = 4)
    html <- gsub("var INLINE_PICKS   = null;  // injected by R",
                 paste0("var INLINE_PICKS   = ", picks_json, ";  // injected by R"),
                 html, fixed = TRUE)
    html <- gsub("var INLINE_PAPER   = null;  // injected by R",
                 paste0("var INLINE_PAPER   = ", paper_json, ";  // injected by R"),
                 html, fixed = TRUE)
    html <- gsub("var INLINE_SUMMARY = null;  // injected by R",
                 paste0("var INLINE_SUMMARY = ", summary_json, ";  // injected by R"),
                 html, fixed = TRUE)
    writeLines(html, html_path)
    cat(sprintf("HTML: inline data injected into %s (%d picks)\n",
                basename(html_path), nrow(final_picks_clean)))
  } else {
    cat("HTML: arcvest_dashboard.html not found - skipping\n")
  }
}, error = function(e) message("HTML inline injection failed: ", e$message))


