# ============================================================
# MARCH MADNESS BRACKET SIMULATOR
# tools/march_madness_sim.R
#
# Usage:
#   1. source("SureBet.R")  ← loads ncaab_standings + sim_tournament()
#   2. source("tools/march_madness_sim.R")
#   3. Fill in bracket_2026 tribble below with tonight's Selection Sunday results
#   4. Run: results <- sim_ncaab_tournament(bracket_2026, ncaab_standings)
#   5. Run: print_bracket_results(results)
#   6. Run: find_bracket_value(results)  ← compares vs futures odds
#
# How it works:
#   - Reuses sim_tournament() from SureBet.R (Sackmann single-elim sim)
#   - Replaces Elo with pyth_winpct converted to pseudo-Elo scale
#   - Preserves bracket seeding order so matchups are correct
#   - 50,000 simulations per run (~2-3 seconds)
#   - Outputs: P(win championship), P(reach Final Four), P(reach Elite Eight),
#              P(reach Sweet 16), P(win first game) for all 64 teams
# ============================================================

library(tidyverse)

# ── Pyth → pseudo-Elo conversion ─────────────────────────────────────────────
# sim_tournament() uses calc_h2h_prob(elo_a, elo_b, e=1.1).
# We need pyth_winpct to behave correctly in h2h matchups.
# Conversion: pseudo_elo = 1000 * pyth_winpct^(1/e)
# This ensures calc_h2h_prob(pa, pb) ≈ pyth_a / (pyth_a + pyth_b) for e=1.
# With e=1.1, slight separation amplification — defensible for tournament play.
NCAAB_ELO_SCALE <- 1000
NCAAB_SIM_E     <- 1.0    # Use e=1.0 for NCAAB (Pythagorean, not surface-adjusted)
NCAAB_SIMS      <- 50000

pyth_to_pseudo_elo <- function(pyth_winpct, scale = NCAAB_ELO_SCALE) {
  # Maps 0.3-0.8 win% range to ~300-800 pseudo-Elo range
  # Preserves relative ordering and h2h math
  pmax(pyth_winpct, 0.01) * scale
}

# ── Round tracker — 64-team bracket has 6 rounds ─────────────────────────────
# Round 1: 64→32  (Round of 64)
# Round 2: 32→16  (Round of 32)
# Round 3: 16→8   (Sweet 16)
# Round 4: 8→4    (Elite Eight)
# Round 5: 4→2    (Final Four)
# Round 6: 2→1    (Championship)

# ── Enhanced sim_tournament for NCAAB — tracks all 6 rounds ──────────────────
sim_ncaab_bracket <- function(draw_df, sims = NCAAB_SIMS, e = NCAAB_SIM_E) {

  players <- draw_df$player
  elo_vec <- setNames(draw_df$elo, draw_df$player)
  n       <- length(players)

  if (n != 64) {
    warning(sprintf("Expected 64 teams, got %d. Proceeding anyway.", n))
  }

  # Round accumulators
  r1_count  <- setNames(integer(n), players)  # Win R1 (reach R32)
  r2_count  <- setNames(integer(n), players)  # Win R2 (reach S16)
  r3_count  <- setNames(integer(n), players)  # Win R3 (reach E8)
  r4_count  <- setNames(integer(n), players)  # Win R4 (reach FF)
  r5_count  <- setNames(integer(n), players)  # Win R5 (reach Championship)
  r6_count  <- setNames(integer(n), players)  # Win R6 (Champion)

  for (sim in seq_len(sims)) {
    current_round <- players
    round_num     <- 0L

    while (length(current_round) > 1) {
      round_num  <- round_num + 1L
      n_matches  <- length(current_round) / 2
      next_round <- character(n_matches)

      for (i in seq_len(n_matches)) {
        p1  <- current_round[2*i - 1]
        p2  <- current_round[2*i]
        e1  <- as.numeric(elo_vec[p1])
        e2  <- as.numeric(elo_vec[p2])
        wp1 <- (e1^e) / ((e1^e) + (e2^e))
        winner <- if (runif(1) < wp1) p1 else p2
        next_round[i] <- winner
      }

      # Track who won each round
      for (p in next_round) {
        if (round_num == 1L) r1_count[p] <- r1_count[p] + 1L
        if (round_num == 2L) r2_count[p] <- r2_count[p] + 1L
        if (round_num == 3L) r3_count[p] <- r3_count[p] + 1L
        if (round_num == 4L) r4_count[p] <- r4_count[p] + 1L
        if (round_num == 5L) r5_count[p] <- r5_count[p] + 1L
        if (round_num == 6L) r6_count[p] <- r6_count[p] + 1L
      }

      current_round <- next_round
    }
  }

  draw_df %>%
    mutate(
      p_win_r1       = r1_count[player] / sims,  # P(win first game)
      p_sweet16      = r2_count[player] / sims,  # P(reach Sweet 16)
      p_elite8       = r3_count[player] / sims,  # P(reach Elite Eight)
      p_final4       = r4_count[player] / sims,  # P(reach Final Four)
      p_championship = r5_count[player] / sims,  # P(reach Championship game)
      p_champion     = r6_count[player] / sims   # P(win it all)
    )
}

# ── Main wrapper: takes bracket + standings, returns full sim results ─────────
sim_ncaab_tournament <- function(bracket_df, standings_df, sims = NCAAB_SIMS) {

  cat(sprintf("\n=== MARCH MADNESS BRACKET SIMULATOR ===\n"))
  cat(sprintf("Teams: %d | Simulations: %s\n", nrow(bracket_df),
              format(sims, big.mark = ",")))

  # Join standings to get pyth_winpct
  bracket_with_pyth <- bracket_df %>%
    left_join(
      standings_df %>%
        select(team_display_name, pyth_winpct, actual_winpct,
               gamesPlayed, wins, ap_rank, coaches_rank),
      by = c("team" = "team_display_name")
    )

  # Warn about unmatched teams
  unmatched <- bracket_with_pyth %>% filter(is.na(pyth_winpct))
  if (nrow(unmatched) > 0) {
    cat(sprintf("\n⚠️  %d teams not found in standings (add to name_crosswalk):\n",
                nrow(unmatched)))
    print(unmatched %>% select(seed, region, team))
    cat("These teams will use seed-based fallback win%.\n")
  }

  # Fallback: estimate pyth from seed (rough but defensible)
  # 1-seed ≈ 0.78, 16-seed ≈ 0.40
  seed_pyth_fallback <- function(seed) {
    0.78 - (seed - 1) * (0.38 / 15)
  }

  bracket_with_pyth <- bracket_with_pyth %>%
    mutate(
      pyth_winpct = if_else(is.na(pyth_winpct),
                            seed_pyth_fallback(seed),
                            pyth_winpct),
      pseudo_elo  = pyth_to_pseudo_elo(pyth_winpct)
    )

  # Build draw_df in bracket order (position = bracket slot)
  # bracket_df must have a 'bracket_slot' column (1-64) defining matchup order
  draw_df <- bracket_with_pyth %>%
    arrange(bracket_slot) %>%
    transmute(
      player = team,
      elo    = pseudo_elo,
      seed,
      region,
      pyth_winpct,
      actual_winpct,
      ap_rank,
      coaches_rank
    )

  cat("\nRunning simulations...\n")
  start_time <- proc.time()
  results    <- sim_ncaab_bracket(draw_df, sims = sims)
  elapsed    <- (proc.time() - start_time)["elapsed"]
  cat(sprintf("✅ Complete in %.1f seconds\n", elapsed))

  results
}

# ── Pretty printer ────────────────────────────────────────────────────────────
print_bracket_results <- function(results, top_n = 64) {
  cat("\n=== SIMULATION RESULTS ===\n")
  cat(sprintf("%-4s %-4s %-30s %8s %8s %8s %8s %8s %8s\n",
              "Seed", "Reg", "Team",
              "R1 Win", "Sweet16", "Elite8",
              "Final4", "Champ Gm", "Champion"))
  cat(strrep("-", 90), "\n")

  results %>%
    arrange(desc(p_champion)) %>%
    head(top_n) %>%
    mutate(across(starts_with("p_"), ~ scales::percent(.x, accuracy = 0.1))) %>%
    with(
      mapply(function(seed, region, player, r1, s16, e8, f4, cg, ch) {
        cat(sprintf("%-4s %-4s %-30s %8s %8s %8s %8s %8s %8s\n",
                    seed, region, player, r1, s16, e8, f4, cg, ch))
      },
      seed, region, player,
      p_win_r1, p_sweet16, p_elite8,
      p_final4, p_championship, p_champion)
    )
  invisible(results)
}

# ── Value finder: compare sim probs vs. futures odds ─────────────────────────
find_bracket_value <- function(results, futures_df = NULL) {
  cat("\n=== CHAMPIONSHIP VALUE BETS ===\n")

  if (!is.null(futures_df)) {
    # Join with actual futures odds if provided
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
      select(seed, region, player, p_champion,
             implied_prob, futures_ml, edge, ev)

    cat(sprintf("%-4s %-4s %-30s %8s %8s %8s %8s %8s\n",
                "Seed", "Reg", "Team",
                "Sim P%", "Impl P%", "ML Odds", "Edge", "EV"))
    cat(strrep("-", 80), "\n")
    print(value)
  } else {
    # No futures odds — just show top championship probabilities
    cat("(No futures odds provided — showing top sim probabilities)\n")
    cat("To add futures: create futures_df with columns team + futures_ml\n\n")
    results %>%
      arrange(desc(p_champion)) %>%
      head(16) %>%
      mutate(
        p_champion_pct = scales::percent(p_champion, accuracy = 0.1)
      ) %>%
      select(seed, region, player, pyth_winpct, p_champion_pct) %>%
      print()
  }
}

# ============================================================
# BRACKET INPUT — fill this in after Selection Sunday tonight
# ============================================================
# Instructions:
#   - bracket_slot: 1-64, defines matchup pairing (1v2, 3v4, etc.)
#     Slots 1-16:  East region  (1v2, 3v4, 5v6, 7v8, 9v10, 11v12, 13v14, 15v16)
#     Slots 17-32: West region
#     Slots 33-48: South region
#     Slots 49-64: Midwest region
#   - seed: 1-16
#   - region: "E", "W", "S", "MW"
#   - team: EXACT name as it appears in ncaab_standings$team_display_name
#     Run: ncaab_standings %>% select(team_display_name) %>% print(n=400) to verify

bracket_2026 <- tribble(
  ~bracket_slot, ~seed, ~region, ~team,
  # ── EAST (1-seed Duke) ────────────────────────────────────
  # First Four note: Siena is listed directly (won/assumed)
   1,  1, "E",  "Duke Blue Devils",
   2, 16, "E",  "Siena Saints",
   3,  8, "E",  "Ohio State Buckeyes",
   4,  9, "E",  "TCU Horned Frogs",
   5,  5, "E",  "St. John's Red Storm",
   6, 12, "E",  "Northern Iowa Panthers",
   7,  4, "E",  "Kansas Jayhawks",
   8, 13, "E",  "California Baptist Lancers",
   9,  6, "E",  "Louisville Cardinals",
  10, 11, "E",  "South Florida Bulls",
  11,  3, "E",  "Michigan State Spartans",
  12, 14, "E",  "North Dakota State Bison",
  13,  7, "E",  "UCLA Bruins",
  14, 10, "E",  "UCF Knights",
  15,  2, "E",  "UConn Huskies",
  16, 15, "E",  "Furman Paladins",
  # ── SOUTH (1-seed Florida) ────────────────────────────────
  # First Four: Prairie View A&M vs Lehigh → using PVAM as placeholder
  17,  1, "S",  "Florida Gators",
  18, 16, "S",  "Prairie View A&M Panthers",
  19,  8, "S",  "Clemson Tigers",
  20,  9, "S",  "Iowa Hawkeyes",
  21,  5, "S",  "Vanderbilt Commodores",
  22, 12, "S",  "McNeese Cowboys",
  23,  4, "S",  "Nebraska Cornhuskers",
  24, 13, "S",  "Troy Trojans",
  25,  6, "S",  "North Carolina Tar Heels",
  26, 11, "S",  "VCU Rams",
  27,  3, "S",  "Illinois Fighting Illini",
  28, 14, "S",  "Pennsylvania Quakers",
  29,  7, "S",  "Saint Mary's Gaels",
  30, 10, "S",  "Texas A&M Aggies",
  31,  2, "S",  "Houston Cougars",
  32, 15, "S",  "Idaho Vandals",
  # ── WEST (1-seed Arizona) ─────────────────────────────────
  # First Four: Texas vs NC State → using Texas as placeholder
  33,  1, "W",  "Arizona Wildcats",
  34, 16, "W",  "Long Island University Sharks",
  35,  8, "W",  "Villanova Wildcats",
  36,  9, "W",  "Utah State Aggies",
  37,  5, "W",  "Wisconsin Badgers",
  38, 12, "W",  "High Point Panthers",
  39,  4, "W",  "Arkansas Razorbacks",
  40, 13, "W",  "Hawai'i Rainbow Warriors",
  41,  6, "W",  "BYU Cougars",
  42, 11, "W",  "Texas Longhorns",
  43,  3, "W",  "Gonzaga Bulldogs",
  44, 14, "W",  "Kennesaw State Owls",
  45,  7, "W",  "Miami Hurricanes",
  46, 10, "W",  "Missouri Tigers",
  47,  2, "W",  "Purdue Boilermakers",
  48, 15, "W",  "Queens University Royals",
  # ── MIDWEST (1-seed Michigan) ─────────────────────────────
  # First Four: UMBC vs Howard → using UMBC; Miami(OH) vs SMU → using Miami(OH)
  49,  1, "MW", "Michigan Wolverines",
  50, 16, "MW", "UMBC Retrievers",
  51,  8, "MW", "Georgia Bulldogs",
  52,  9, "MW", "Saint Louis Billikens",
  53,  5, "MW", "Texas Tech Red Raiders",
  54, 12, "MW", "Akron Zips",
  55,  4, "MW", "Alabama Crimson Tide",
  56, 13, "MW", "Hofstra Pride",
  57,  6, "MW", "Tennessee Volunteers",
  58, 11, "MW", "Miami (OH) RedHawks",
  59,  3, "MW", "Virginia Cavaliers",
  60, 14, "MW", "Wright State Raiders",
  61,  7, "MW", "Kentucky Wildcats",
  62, 10, "MW", "Santa Clara Broncos",
  63,  2, "MW", "Iowa State Cyclones",
  64, 15, "MW", "Tennessee State Tigers"
)

# ============================================================
# FUTURES ODDS — fill in after bracket is set (optional)
# ============================================================
# Get these from DraftKings/FanDuel championship futures market
# Format: decimal odds (e.g. 6.00 = +500)
# Leave NULL to skip value comparison

futures_2026 <- NULL
# Example format when you have odds:
# futures_2026 <- tribble(
#   ~team,                        ~futures_ml,
#   "Duke Blue Devils",           6.00,
#   "Auburn Tigers",              7.50,
#   "Houston Cougars",            8.00,
# )

# ============================================================
# RUN THE SIMULATION
# ============================================================
# Uncomment after filling in bracket_2026 above:

results_2026 <- sim_ncaab_tournament(bracket_2026, ncaab_standings)
print_bracket_results(results_2026)
find_bracket_value(results_2026, futures_2026)

cat("\n✅ March Madness simulator loaded.\n")
cat("Fill in bracket_2026 tribble with tonight's Selection Sunday results,\n")
cat("then run: results_2026 <- sim_ncaab_tournament(bracket_2026, ncaab_standings)\n\n")
