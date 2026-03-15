# ============================================================
# vig_monitor.R — SureBet Bookmaker Vig Monitor
# ============================================================
# Calculates overround (vig) by bookmaker and sport from the
# live TOA odds feed, appends results to a running history
# CSV, and prints a summary report.
#
# Run from the SureBet root directory:
#   setwd("C:/Users/jacks/OneDrive/Documents/SureBet")
#   source("tools/vig_monitor.R")
#
# Requires: SureBet.R must have been sourced first in the
# same R session so multi_odds_filtered is available.
# The vig_monitor can also be called from inside SureBet.R
# after the odds fetch — add source("tools/vig_monitor.R")
# anywhere after the multi_odds_filtered line.
#
# Output files (in tools/reports/):
#   vig_history.csv          — one row per book per sport per day
#   vig_summary_YYYY-MM-DD.csv — today's full summary table
# ============================================================

source("tools/surebet_utils.R")

# ── Guard: multi_odds_filtered must exist ─────────────────────────────────────
if (!exists("multi_odds_filtered")) {
  stop(paste(
    "multi_odds_filtered not found.",
    "Source SureBet.R first, then run this tool.",
    "Or add source('tools/vig_monitor.R') inside SureBet.R after the odds fetch."
  ))
}

# ── Constants ─────────────────────────────────────────────────────────────────
VIG_HISTORY_PATH <- file.path(REPORTS_DIR, "vig_history.csv")
TODAY            <- Sys.Date()
RUN_TIMESTAMP    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")  # ET local time — captures time-of-day for vig trend analysis

# ── Sport grouping helper ─────────────────────────────────────────────────────
classify_sport <- function(sport_key) {
  case_when(
    str_detect(sport_key, "basketball_nba")    ~ "NBA",
    str_detect(sport_key, "basketball_ncaab")  ~ "NCAAB",
    str_detect(sport_key, "icehockey_nhl")     ~ "NHL",
    str_detect(sport_key, "baseball_mlb")      ~ "MLB",
    str_detect(sport_key, "soccer_epl")        ~ "Soccer - EPL",
    str_detect(sport_key, "bundesliga")        ~ "Soccer - Bundesliga",
    str_detect(sport_key, "serie_a")           ~ "Soccer - Serie A",
    str_detect(sport_key, "la_liga")           ~ "Soccer - La Liga",
    str_detect(sport_key, "ligue_one")         ~ "Soccer - Ligue 1",
    str_detect(sport_key, "soccer_usa_mls")    ~ "Soccer - MLS",
    str_detect(sport_key, "champs_league")     ~ "Soccer - UCL",
    str_detect(sport_key, "europa_league")     ~ "Soccer - UEL",
    str_detect(sport_key, "tennis_atp")        ~ "Tennis - ATP",
    str_detect(sport_key, "tennis_wta")        ~ "Tennis - WTA",
    TRUE                                       ~ sport_key
  )
}

# ── Step 1: Calculate vig from live h2h markets ───────────────────────────────
# Vig = overround = sum(implied probabilities) - 1, expressed as a percentage.
# h2h only: two-sided markets give a clean overround calc.
# Soccer is excluded here because h2h has 3 outcomes (home/draw/away);
# a separate 3-way overround is calculated below.

section("Calculating vig from today's odds feed")

# Two-way markets (NBA, NCAAB, NHL, MLB, Tennis)
vig_twoway <- multi_odds_filtered %>%
  filter(market_key == "h2h") %>%
  mutate(
    run_date      = TODAY,
    run_timestamp = RUN_TIMESTAMP,
    game_date     = as.Date(commence_time),
    sport_grp     = classify_sport(sport_key)
  ) %>%
  filter(!str_detect(sport_grp, "Soccer")) %>%
  group_by(run_date, run_timestamp, game_date, sport_grp, sport_key,
           home_team, away_team, bookmaker_key, bookmaker) %>%
  summarise(
    implied_sum = sum(1 / outcomes_price, na.rm = TRUE),
    n_sides     = n(),
    .groups     = "drop"
  ) %>%
  filter(n_sides == 2) %>%
  mutate(
    vig_pct    = (implied_sum - 1) * 100,
    market_type = "2-way"
  )

# Three-way markets (Soccer 1X2)
vig_soccer <- multi_odds_filtered %>%
  filter(market_key == "h2h") %>%
  mutate(
    run_date      = TODAY,
    run_timestamp = RUN_TIMESTAMP,
    game_date     = as.Date(commence_time),
    sport_grp     = classify_sport(sport_key)
  ) %>%
  filter(str_detect(sport_grp, "Soccer")) %>%
  group_by(run_date, run_timestamp, game_date, sport_grp, sport_key,
           home_team, away_team, bookmaker_key, bookmaker) %>%
  summarise(
    implied_sum = sum(1 / outcomes_price, na.rm = TRUE),
    n_sides     = n(),
    .groups     = "drop"
  ) %>%
  filter(n_sides == 3) %>%
  mutate(
    vig_pct     = (implied_sum - 1) * 100,
    market_type = "3-way"
  )

vig_all <- bind_rows(vig_twoway, vig_soccer)

cat(sprintf("Markets analysed: %d two-way | %d three-way (soccer)\n",
            nrow(vig_twoway), nrow(vig_soccer)))

# ── Step 2: Summary by bookmaker (overall) ────────────────────────────────────
section("Overall vig by bookmaker")

vig_by_book <- vig_all %>%
  group_by(bookmaker_key, bookmaker) %>%
  summarise(
    avg_vig    = round(mean(vig_pct,   na.rm = TRUE), 2),
    median_vig = round(median(vig_pct, na.rm = TRUE), 2),
    min_vig    = round(min(vig_pct,    na.rm = TRUE), 2),
    max_vig    = round(max(vig_pct,    na.rm = TRUE), 2),
    n_markets  = n(),
    .groups    = "drop"
  ) %>%
  arrange(avg_vig) %>%
  mutate(rank = row_number())

print(vig_by_book %>%
        select(rank, bookmaker, avg_vig, median_vig, min_vig, max_vig, n_markets),
      n = Inf)

# ── Step 3: Summary by bookmaker × sport ─────────────────────────────────────
section("Vig by bookmaker × sport")

vig_by_book_sport <- vig_all %>%
  group_by(sport_grp, bookmaker_key, bookmaker) %>%
  summarise(
    avg_vig   = round(mean(vig_pct, na.rm = TRUE), 2),
    n_markets = n(),
    .groups   = "drop"
  ) %>%
  arrange(sport_grp, avg_vig)

print(vig_by_book_sport, n = Inf)

# ── Step 4: Cheapest book per sport ──────────────────────────────────────────
section("Cheapest book per sport (lowest avg vig)")

cheapest_by_sport <- vig_by_book_sport %>%
  group_by(sport_grp) %>%
  slice_min(avg_vig, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(sport_grp, bookmaker, avg_vig, n_markets) %>%
  arrange(sport_grp)

print(cheapest_by_sport, n = Inf)

# ── Step 5: Vig spread — most vs least expensive book per market ──────────────
section("Vig spread within each sport (best vs worst book)")

vig_spread <- vig_by_book_sport %>%
  group_by(sport_grp) %>%
  summarise(
    cheapest_book = bookmaker[which.min(avg_vig)],
    cheapest_vig  = min(avg_vig),
    priciest_book = bookmaker[which.max(avg_vig)],
    priciest_vig  = max(avg_vig),
    spread_pts    = round(max(avg_vig) - min(avg_vig), 2),
    .groups       = "drop"
  ) %>%
  arrange(desc(spread_pts))

print(vig_spread, n = Inf)
cat("\nLarger spread = more opportunity to shop lines across books for that sport.\n")

# ── Step 6: Append to running history CSV ────────────────────────────────────
section("Appending to vig history")

# Row-level history: one row per book × sport per run_date
history_new <- vig_all %>%
  group_by(run_date, run_timestamp, sport_grp, market_type, bookmaker_key, bookmaker) %>%
  summarise(
    avg_vig    = round(mean(vig_pct,   na.rm = TRUE), 2),
    median_vig = round(median(vig_pct, na.rm = TRUE), 2),
    n_markets  = n(),
    .groups    = "drop"
  )

if (file.exists(VIG_HISTORY_PATH)) {
  history_existing <- read_csv(VIG_HISTORY_PATH,
                                col_types = cols(
                                  run_date      = col_date(),
                                  run_timestamp = col_character(),
                                  .default      = col_guess()
                                ),
                                show_col_types = FALSE)

  # Guard: if existing file was written before run_timestamp column existed,
  # add it so bind_rows and group_by don't fail. Self-healing — only triggers once.
  if (!"run_timestamp" %in% names(history_existing)) {
    history_existing <- history_existing %>%
      mutate(run_timestamp = NA_character_)
  }

  # Remove today's rows if re-running (idempotent)
  history_existing <- history_existing %>%
    filter(run_date != TODAY)   # removes all of today's rows before re-appending

  history_combined <- bind_rows(history_existing, history_new)
} else {
  history_combined <- history_new
}

write_csv(history_combined, VIG_HISTORY_PATH)
cat(sprintf("Vig history updated: %d total rows → %s\n",
            nrow(history_combined), VIG_HISTORY_PATH))

# Also write today's full detail to a dated summary file
today_summary_path <- file.path(REPORTS_DIR,
                                 paste0("vig_summary_", TODAY, ".csv"))
write_csv(vig_by_book_sport, today_summary_path)
cat(sprintf("Today's summary written → %s\n", today_summary_path))

# ── Step 7: Trend report (if history has multiple days) ───────────────────────
if (nrow(history_combined) > nrow(history_new)) {

  section("Vig trend (all history)")

  trend <- history_combined %>%
    group_by(run_date, run_timestamp) %>%
    summarise(
      avg_vig_all_books = round(mean(avg_vig, na.rm = TRUE), 2),
      n_book_sport_rows = n(),
      .groups = "drop"
    ) %>%
    arrange(run_date, run_timestamp)

  cat("Date-level average vig across all books and sports:\n\n")
  print(trend, n = Inf)

  # Per-book trend
  book_trend <- history_combined %>%
    group_by(bookmaker, run_date) %>%
    summarise(avg_vig = round(mean(avg_vig, na.rm = TRUE), 2),
              .groups = "drop") %>%
    pivot_wider(names_from = run_date, values_from = avg_vig) %>%
    arrange(across(last_col()))

  cat("\nPer-book vig by date (most recent rightmost):\n\n")
  print(book_trend, n = Inf)
}

section("Vig monitor complete")
cat(sprintf("Run date/time: %s\n", RUN_TIMESTAMP))
cat(sprintf("Books analysed: %d\n", n_distinct(vig_all$bookmaker_key)))
cat(sprintf("Total markets: %d\n", nrow(vig_all)))
