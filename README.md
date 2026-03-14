# SureBet Archer

A quantitative sports betting advisory engine built in R. Treats sports betting as a portfolio management problem — individual bets weighted like stocks, sports weighted like sectors.

## What it does

Runs a daily pipeline across NBA, NCAAB, NHL, MLB, Soccer (8 leagues), ATP/WTA Tennis, and Challenger Tennis:

1. **Fetches live odds** from The Odds API across all books
2. **Models win probability** using sport-specific Pythagorean expectation, Elo ratings (tennis), and BaseRuns (MLB)
3. **Filters through a 2-gate system** — minimum 5% expected value AND positive edge vs. no-vig probability
4. **Sizes stakes** using fractional Kelly criterion (quarter Kelly)
5. **Applies a 10% daily bankroll risk cap** via uniform scaling — all gate-passing bets scaled proportionally, none dropped by priority rank
6. **Logs picks** and **settles results** against ESPN scores
7. **Tracks performance** in a paper trading dashboard

## Repository structure

```
SureBetPro/
├── SureBet.R                  # Daily engine — odds fetch → model → picks → settle
├── surebet_dashboard.R        # Shiny dashboard — paper log, picks, ROI trend
├── tools/
│   ├── surebet_utils.R        # Shared loaders and helpers for all tool scripts
│   └── vig_monitor.R          # Bookmaker overround tracking by sport and book
└── tools/reports/             # Generated reports (local only, not committed)
```

## Setup

**Requirements:** R 4.x, tidyverse, oddsapiR, hoopR, fastRhockey, worldfootballR, readxl, DT, shiny

**Working directory:** Set to your SureBetPro root before running:
```r
setwd("C:/path/to/SureBetPro")
source("SureBet.R")
```

**API key:** The Odds API key must be set in your `.Renviron` file:
```
ODDS_API_KEY=your_key_here
```

**Data files required** (not committed — obtain separately):
- `TENDATAUPLOAD.xlsx` — Challenger tennis draws and Elo ratings (manual update each round)
- `2025MLBRef.xlsx` — MLB preseason reference data (replaced by live API on March 27)

## Paper trading

Reset to $1,000 bankroll on 2026-03-13. Prior logs archived in `logs/archive/`.

`STARTING_BANKROLL` is set near the bottom of `SureBet.R`. Update this value and delete `logs/paper_trading_log.csv` to reset.

## Tools

Each script in `tools/` is standalone — run manually from the console after `source("SureBet.R")`, or called automatically at the end of the daily run.

`vig_monitor.R` runs automatically and appends to `tools/reports/vig_history.csv` with a timestamp so time-of-day vig patterns can be tracked over time.

## Roadmap (parking lot)

- **March 27:** Flip MLB pipeline from preseason to live season
- **High priority:** Reliable game start times — TOA returns midnight UTC for unconfirmed tip times; Challenger times need timezone fix
- **Future:** Sport-level Kelly multipliers (sector tilts) once sufficient data exists
- **NFL/NCAAF season:** Key number push probability adjustments for spreads and totals
- **Stage 2:** JSON exports → static HTML/CSS/JS dashboard, no server required
- **Stage 3:** Hosted web app + subscription picks delivery
- **Stage 4:** PWA or mobile app

## Status

Paper trading since 2026-03-13. Engine stable, no open bugs as of last commit.
