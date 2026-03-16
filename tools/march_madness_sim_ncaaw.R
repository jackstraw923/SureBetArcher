# ============================================================
# WOMEN'S MARCH MADNESS BRACKET SIMULATOR
# tools/march_madness_sim_ncaaw.R
#
# Usage:
#   1. source("SureBet.R")  <- loads ncaab_standings + sim infrastructure
#   2. source("tools/march_madness_sim_ncaaw.R")
#   3. Run: results_w <- sim_ncaaw_tournament(bracket_w2026_matched, ncaaw_standings)
#   4. Run: print_bracket_results_w(results_w)
#   5. Run: find_bracket_value_w(results_w, futures_w2026)
#
# Suppression gate (SureBet.R):
#   NCAAW_LIVE_DATE <- as.Date("2026-03-17")
#   Picks excluded from all_picks_df until Sys.Date() >= NCAAW_LIVE_DATE.
#   Sim still runs + logs to ncaaw_bet_log_YYYY-MM-DD.csv every day.
#
# First Four update (March 18-19):
#   Slots 26, 34, 50, 62 hold FF placeholders. After games complete,
#   replace the placeholder team with the actual winner.
# ============================================================

library(tidyverse)
library(wehoop)

# ── Constants ────────────────────────────────────────────────────────────────
NCAAW_ELO_SCALE <- 1000
NCAAW_SIM_E     <- 1.0
NCAAW_SIMS      <- 50000

pyth_to_pseudo_elo_w <- function(pyth_winpct, scale = NCAAW_ELO_SCALE) {
  pmax(pyth_winpct, 0.01) * scale
}

# ── Standings fetch ───────────────────────────────────────────────────────────
fetch_ncaaw_standings <- function(season = 2026) {
  tryCatch({
    raw <- wehoop::espn_wbb_standings()
    raw %>%
      as_tibble() %>%
      mutate(
        games_played  = as.integer(wins) + as.integer(losses),
        actual_winpct = as.numeric(wins) / pmax(games_played, 1),
        pyth_exp      = 10,
        pyth_winpct   = if ("points_for" %in% names(.) &
                            "points_against" %in% names(.)) {
          pf <- as.numeric(points_for)
          pa <- as.numeric(points_against)
          pf^pyth_exp / (pf^pyth_exp + pa^pyth_exp)
        } else {
          actual_winpct
        }
      ) %>%
      select(team_display_name, games_played, wins, losses,
             actual_winpct, pyth_winpct)
  }, error = function(e) {
    message("WARNING: NCAAW standings fetch failed: ", e$message)
    message("  Falling back to seed-based estimates.")
    tibble(team_display_name = character(), games_played = integer(),
           wins = integer(), losses = integer(),
           actual_winpct = double(), pyth_winpct = double())
  })
}

# ── Core sim ──────────────────────────────────────────────────────────────────
sim_ncaaw_bracket <- function(draw_df, sims = NCAAW_SIMS, e = NCAAW_SIM_E) {
  players <- draw_df$player
  elo_vec <- setNames(draw_df$elo, draw_df$player)
  n       <- length(players)
  if (n != 64) warning(sprintf("Expected 64 teams, got %d.", n))

  r1 <- r2 <- r3 <- r4 <- r5 <- r6 <- setNames(integer(n), players)

  for (sim in seq_len(sims)) {
    curr <- players
    rnd  <- 0L
    while (length(curr) > 1) {
      rnd  <- rnd + 1L
      nm   <- length(curr) / 2
      next_r <- character(nm)
      for (i in seq_len(nm)) {
        p1  <- curr[2*i - 1]; p2 <- curr[2*i]
        e1  <- as.numeric(elo_vec[p1]); e2 <- as.numeric(elo_vec[p2])
        wp1 <- (e1^e) / ((e1^e) + (e2^e))
        next_r[i] <- if (runif(1) < wp1) p1 else p2
      }
      for (p in next_r) {
        if (rnd == 1L) r1[p] <- r1[p] + 1L
        if (rnd == 2L) r2[p] <- r2[p] + 1L
        if (rnd == 3L) r3[p] <- r3[p] + 1L
        if (rnd == 4L) r4[p] <- r4[p] + 1L
        if (rnd == 5L) r5[p] <- r5[p] + 1L
        if (rnd == 6L) r6[p] <- r6[p] + 1L
      }
      curr <- next_r
    }
  }

  draw_df %>%
    mutate(
      p_win_r1       = r1[player] / sims,
      p_sweet16      = r2[player] / sims,
      p_elite8       = r3[player] / sims,
      p_final4       = r4[player] / sims,
      p_championship = r5[player] / sims,
      p_champion     = r6[player] / sims
    )
}

# ── Main wrapper ──────────────────────────────────────────────────────────────
sim_ncaaw_tournament <- function(bracket_df, standings_df, sims = NCAAW_SIMS) {
  cat("\n=== WOMEN'S MARCH MADNESS BRACKET SIMULATOR ===\n")
  cat(sprintf("Teams: %d | Simulations: %s\n", nrow(bracket_df),
              format(sims, big.mark = ",")))

  bwp <- bracket_df %>%
    left_join(
      standings_df %>% select(team_display_name, pyth_winpct, actual_winpct,
                               games_played, wins),
      by = c("team" = "team_display_name")
    )

  unmatched <- bwp %>% filter(is.na(pyth_winpct))
  if (nrow(unmatched) > 0) {
    cat(sprintf("\nWARNING: %d teams not in standings (add to ncaaw_name_crosswalk):\n",
                nrow(unmatched)))
    print(unmatched %>% select(seed, region, team))
    cat("Using seed-based fallback.\n")
  }

  seed_fallback <- function(s) 0.82 - (s - 1) * (0.42 / 15)

  draw_df <- bwp %>%
    mutate(
      pyth_winpct = if_else(is.na(pyth_winpct), seed_fallback(seed), pyth_winpct),
      pseudo_elo  = pyth_to_pseudo_elo_w(pyth_winpct)
    ) %>%
    arrange(bracket_slot) %>%
    transmute(player = team, elo = pseudo_elo, seed, region,
              pyth_winpct, actual_winpct)

  cat("\nRunning simulations...\n")
  t0  <- proc.time()
  res <- sim_ncaaw_bracket(draw_df, sims = sims)
  cat(sprintf("Complete in %.1f seconds\n", (proc.time() - t0)["elapsed"]))
  res
}

# ── Printers ──────────────────────────────────────────────────────────────────
print_bracket_results_w <- function(results, top_n = 64) {
  cat("\n=== WOMEN'S SIMULATION RESULTS ===\n")
  cat(sprintf("%-4s %-4s %-35s %8s %8s %8s %8s %8s %8s\n",
              "Seed","Reg","Team","R1 Win","Sweet16","Elite8",
              "Final4","Champ Gm","Champion"))
  cat(strrep("-", 95), "\n")
  results %>%
    arrange(desc(p_champion)) %>% head(top_n) %>%
    mutate(across(starts_with("p_"), ~ scales::percent(.x, accuracy = 0.1))) %>%
    with(mapply(function(s,r,p,r1,s16,e8,f4,cg,ch)
      cat(sprintf("%-4s %-4s %-35s %8s %8s %8s %8s %8s %8s\n",
                  s,r,p,r1,s16,e8,f4,cg,ch)),
      seed,region,player,p_win_r1,p_sweet16,p_elite8,
      p_final4,p_championship,p_champion))
  invisible(results)
}

find_bracket_value_w <- function(results, futures_df = NULL) {
  cat("\n=== WOMEN'S CHAMPIONSHIP VALUE BETS ===\n")
  if (!is.null(futures_df)) {
    value <- results %>%
      left_join(futures_df, by = c("player" = "team")) %>%
      filter(!is.na(futures_ml)) %>%
      mutate(
        implied_prob = 1 / futures_ml,
        edge         = p_champion - implied_prob,
        ev           = p_champion * futures_ml - 1
      ) %>%
      filter(ev > 0) %>%
      arrange(desc(ev)) %>%
      select(seed, region, player, p_champion, implied_prob, futures_ml, edge, ev)
    print(value)
  } else {
    cat("(No futures odds — showing top sim probabilities)\n\n")
    results %>%
      arrange(desc(p_champion)) %>% head(16) %>%
      mutate(p_pct = scales::percent(p_champion, accuracy = 0.1)) %>%
      select(seed, region, player, pyth_winpct, p_pct) %>%
      print()
  }
}

# ============================================================
# NCAAW NAME CROSSWALK
# ============================================================
# Maps bracket display names -> wehoop::espn_wbb_standings team_display_name.
# Run: ncaaw_standings %>% select(team_display_name) to verify.
# Add rows as WARNING output surfaces new mismatches.

ncaaw_name_crosswalk <- tribble(
  ~bracket_name,                        ~hoopR_name,
  "UConn Huskies",                      "Connecticut Huskies",
  "Tennessee Volunteers",               "Tennessee Lady Vols",
  "Missouri State Bears",               "Missouri State Lady Bears",
  "Cal Baptist Lancers",                "California Baptist Lancers",
  "Oklahoma State Cowgirls",            "Oklahoma State Cowgirls",
  "Ole Miss Rebels",                    "Mississippi Rebels",
  "South Dakota State Jackrabbits",     "South Dakota State Jackrabbits",
  "FDU Knights",                        "Fairleigh Dickinson Knights",
  "NC State Wolfpack",                  "North Carolina State Wolfpack"
)

# ============================================================
# 2026 WOMEN'S BRACKET
# ============================================================
# Source: Official ESPN bracket PDF confirmed March 15, 2026
#
# Regions:
#   FW1 = Fort Worth 1  — UConn    (Storrs host  -> Fort Worth  regional)
#   SC2 = Sacramento 2  — UCLA     (LA host      -> Sacramento  regional)
#   FW3 = Fort Worth 3  — Texas    (Austin host  -> Fort Worth  regional)
#   SC4 = Sacramento 4  — SC       (Columbia host-> Sacramento  regional)
#
# First Four placeholders (update slots after March 18-19 results):
#   Slot 10: Nebraska or Richmond  (11-seed, plays into UConn bracket)
#   Slot 34: Missouri St or SF Austin (16-seed, plays Texas)
#   Slot 50: Southern or Samford   (16-seed, plays SC)
#   Slot 62: Virginia or Arizona St (10-seed, plays Iowa in SC bracket)
#
# Bracket slot order within each region:
#   1v2, 3v4, 5v6, 7v8, 9v10, 11v12, 13v14, 15v16
#   (seeds 1&16 in slots 1&2, seeds 8&9 in slots 3&4, etc.)

bracket_w2026 <- tribble(
  ~bracket_slot, ~seed, ~region, ~team,

  # ── FORT WORTH 1 (FW1): UConn ────────────────────────────────────────────
   1,  1, "FW1", "UConn Huskies",
   2, 16, "FW1", "UTSA Roadrunners",
   3,  8, "FW1", "Iowa State Cyclones",
   4,  9, "FW1", "Syracuse Orange",
   5,  5, "FW1", "Maryland Terrapins",
   6, 12, "FW1", "Murray State Racers",
   7,  4, "FW1", "North Carolina Tar Heels",
   8, 13, "FW1", "Western Illinois Leathernecks",
   9,  6, "FW1", "Notre Dame Fighting Irish",
  10, 11, "FW1", "Fairfield Stags",
  11,  3, "FW1", "Ohio State Buckeyes",
  12, 14, "FW1", "Howard Bison",
  13,  7, "FW1", "Illinois Fighting Illini",
  14, 10, "FW1", "Colorado Buffaloes",
  15,  2, "FW1", "Vanderbilt Commodores",
  16, 15, "FW1", "High Point Panthers",

  # ── SACRAMENTO 2 (SC2): UCLA ─────────────────────────────────────────────
  17,  1, "SC2", "UCLA Bruins",
  18, 16, "SC2", "Cal Baptist Lancers",
  19,  8, "SC2", "Oklahoma State Cowgirls",
  20,  9, "SC2", "Princeton Tigers",
  21,  5, "SC2", "Ole Miss Rebels",
  22, 12, "SC2", "Gonzaga Bulldogs",
  23,  4, "SC2", "Minnesota Golden Gophers",
  24, 13, "SC2", "Green Bay Phoenix",
  25,  6, "SC2", "Baylor Bears",
  26, 11, "SC2", "Nebraska Cornhuskers",          # FF placeholder: Nebraska vs Richmond
  27,  3, "SC2", "Duke Blue Devils",
  28, 14, "SC2", "Charleston Cougars",
  29,  7, "SC2", "Texas Tech Red Raiders",
  30, 10, "SC2", "Villanova Wildcats",
  31,  2, "SC2", "LSU Tigers",
  32, 15, "SC2", "Jacksonville Dolphins",

  # ── FORT WORTH 3 (FW3): Texas ────────────────────────────────────────────
  33,  1, "FW3", "Texas Longhorns",
  34, 16, "FW3", "Missouri State Bears",       # FF placeholder: Missouri St vs SF Austin
  35,  8, "FW3", "Oregon Ducks",
  36,  9, "FW3", "Virginia Tech Hokies",
  37,  5, "FW3", "Kentucky Wildcats",
  38, 12, "FW3", "James Madison Dukes",
  39,  4, "FW3", "West Virginia Mountaineers",
  40, 13, "FW3", "Miami (OH) RedHawks",
  41,  6, "FW3", "Alabama Crimson Tide",
  42, 11, "FW3", "Rhode Island Rams",
  43,  3, "FW3", "Louisville Cardinals",
  44, 14, "FW3", "Vermont Catamounts",
  45,  7, "FW3", "NC State Wolfpack",
  46, 10, "FW3", "Tennessee Volunteers",
  47,  2, "FW3", "Michigan Wolverines",
  48, 15, "FW3", "Holy Cross Crusaders",

  # ── SACRAMENTO 4 (SC4): South Carolina ───────────────────────────────────
  49,  1, "SC4", "South Carolina Gamecocks",
  50, 16, "SC4", "Southern Jaguars",           # FF placeholder: Southern vs Samford
  51,  8, "SC4", "Clemson Tigers",
  52,  9, "SC4", "USC Trojans",
  53,  5, "SC4", "Michigan State Spartans",
  54, 12, "SC4", "Colorado State Rams",
  55,  4, "SC4", "Oklahoma Sooners",
  56, 13, "SC4", "Idaho Vandals",
  57,  6, "SC4", "Washington Huskies",
  58, 11, "SC4", "South Dakota State Jackrabbits",
  59,  3, "SC4", "TCU Horned Frogs",
  60, 14, "SC4", "UC San Diego Tritons",
  61,  7, "SC4", "Georgia Bulldogs",
  62, 10, "SC4", "Arizona State Sun Devils",    # FF placeholder: Virginia vs Arizona St
  63,  2, "SC4", "Iowa Hawkeyes",
  64, 15, "SC4", "FDU Knights"
)

# ============================================================
# FUTURES ODDS
# ============================================================
futures_w2026 <- tribble(
  ~team,                        ~futures_ml,
  "UConn Huskies",              1.34,   # FanDuel -290
  "South Carolina Gamecocks",   3.90,   # +290
  "UCLA Bruins",                5.25,   # +425
  "Texas Longhorns",            9.00    # +800
)

# ============================================================
# RUN
# ============================================================

cat("\nFetching NCAAW standings via hoopR...\n")
ncaaw_standings <- fetch_ncaaw_standings()
cat(sprintf("NCAAW standings: %d teams loaded\n", nrow(ncaaw_standings)))

# Apply crosswalk
bracket_w2026_matched <- bracket_w2026 %>%
  left_join(ncaaw_name_crosswalk, by = c("team" = "bracket_name")) %>%
  mutate(team = coalesce(hoopR_name, team)) %>%
  select(-hoopR_name)

results_w2026 <- sim_ncaaw_tournament(bracket_w2026_matched, ncaaw_standings)
print_bracket_results_w(results_w2026)
find_bracket_value_w(results_w2026, futures_w2026)

# ── Save results for SureBet.R to read daily (no re-sim needed) ──────────────
ncaaw_results_path <- file.path("tools", "ncaaw_sim_results.csv")
write_csv(results_w2026, ncaaw_results_path)
cat(sprintf("\nSim results saved -> %s\n", ncaaw_results_path))
cat("SureBet.R will read this file daily for NCAAW value bets.\n")
cat("Re-run this script after each round to update probabilities.\n")

cat("\nWomen's March Madness simulator complete.\n")
cat("First Four updates needed after March 18-19:\n")
cat("  Slot 10: Nebraska vs Richmond winner\n")
cat("  Slot 34: Missouri State vs SF Austin winner\n")
cat("  Slot 50: Southern vs Samford winner\n")
cat("  Slot 62: Virginia vs Arizona State winner\n\n")
