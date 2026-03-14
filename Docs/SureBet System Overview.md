# SureBet System Overview

## Project Purpose
SureBet Pro is a quantitative sports investing platform automating model-driven value detection, Kelly-sized position sizing, and portfolio risk management across 10+ sports. Treats betting like stock picking with transparent Pythagorean models, edge filters, and fractional Kelly.[file:1][file:5]

## High-Level Pipeline Flow
START → Odds Fetch (Odds API) → Per-Sport Models → Enrichment → Value (2-Gate) → Kelly Sizing → Logs → Settlement (ESPN) → Paper Dashboard → END

text

## Core Architecture
- **Single R Script**: `SureBet.R` (~130k chars), tidyverse + oddsapiR/hoopR/fastRhockey/worldfootballR.
- **Data Flow**: multioddsfiltered → standings join → no-vig/EV/edge → dedup best-book → scaledkelly → CSVs.
- **Daily Cycle**: Place today’s bets + settle yesterday’s.

## Sports Status
| Sport   | Standings | Model                  | Value Bets | Notes |
|---------|-----------|------------------------|------------|-------|
| NBA    | ✅       | PythagenPat 14.3      | ✅ ML/S/T  | Full |
| NCAAB  | ✅       | PythagenPat 10-12     | ✅ ML/S/T  | Rankings |
| NHL    | ✅       | PythagenPuck 0.458    | ✅ ML/S/T  | Full |
| Soccer | ✅       | League exp + draws    | ✅ 3-way   | Double-chance queued |
| MLB    | ✅       | Pyth+BaseRuns         | Partial   | Preseason |

## Decision Trees
**Value Filter**:
Model Prob → No-Vig Book Prob → Edge >5%? → +EV? → LOG BET

text
**Kelly**:
Raw Kelly/4 → Sum All → sf = min(1, 0.1/sum) → scaledkelly

text
**Settlement**:
Logs → ESPN Scores → W/L → Dollar PnL → Paper Log

text

## Current State (Mar 9, 2026)
- **Live**: 200+ daily picks, +4.3% paper ROI (15W-12L).
- **Bugs**: Name joins, NA pyth, settlement edges.
- **Next**: Bug fixes → Tennis → GUI.

**Onboard**: Run `SureBet.R`, review CSVs, place top picks.

Generated: Perplexity Pro, Mar 9, 2026