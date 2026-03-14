# SureBet Log Reset Instructions
**Date:** 2026-03-13  
**Reason:** 3/10 logs corrupted by old-format duplicate rows. Fresh start with verified math and clean dedup guard.

---

## Step 1 — Archive Old Logs

Open a terminal / File Explorer and run these commands from:  
`C:\Users\jacks\OneDrive\Documents\SureBet\`

```
mkdir logs\archive
move logs\bet_log_2026-03-10.csv          logs\archive\
move logs\spread_total_log_2026-03-10.csv logs\archive\   (if it exists)
move logs\soccer_bet_log_2026-03-10.csv   logs\archive\   (if it exists)
move logs\tennis_bet_log_2026-03-10.csv   logs\archive\   (if it exists)
move logs\challenger_picks_2026-03-10.csv logs\archive\   (if it exists)
move logs\mlb_bet_log_2026-03-10.csv      logs\archive\   (if it exists)
```

**Also archive 3/11 logs** (small sample, model not yet confirmed edge — clean slate is better):
```
move logs\bet_log_2026-03-11.csv          logs\archive\
move logs\spread_total_log_2026-03-11.csv logs\archive\
move logs\soccer_bet_log_2026-03-11.csv   logs\archive\
move logs\tennis_bet_log_2026-03-11.csv   logs\archive\
move logs\challenger_picks_2026-03-11.csv logs\archive\
move logs\mlb_bet_log_2026-03-11.csv      logs\archive\   (if it exists)
```

---

## Step 2 — Delete paper_trading_log.csv

```
del logs\paper_trading_log.csv
```

The script will auto-recreate it fresh on next run.  
`STARTING_BANKROLL = $1,000.00` — baseline resets to today.

---

## Step 3 — Apply Updated SureBet.R

Replace your local `SureBet.R` with the version downloaded from this session.

**Changes in this version:**
- `write_bet_log()` — dedup assertion added: warns and auto-fixes if any duplicate game/side combos sneak through the pipeline
- `write_spread_total_log()` — same dedup guard added
- NCAAB crosswalk — 2 new entries: `San Jose State Spartans → San José State Spartans`, `Prairie View Panthers → Prairie View A&M Panthers`
- `STARTING_BANKROLL` comment updated with reset date

---

## Step 4 — Run SureBet.R

Run the script as normal. Expected clean-start output:

```
✅ Bet log created: N ML positions → logs/bet_log_2026-03-13.csv
✅ Spread/total log created: N spread/total positions → logs/spread_total_log_2026-03-13.csv
Soccer bet log written: logs/soccer_bet_log_2026-03-13.csv
Tennis bet log written: logs/tennis_bet_log_2026-03-13.csv
Challenger bet log written: logs/challenger_picks_2026-03-13.csv

Paper trading log initialized.      ← fresh start
Backfill candidates: 0 dates        ← no stale logs to backfill
Current paper bankroll: $ 1000.00   ← clean baseline
```

---

## Step 5 — Verify Dedup Guard

After the run, open `logs/bet_log_2026-03-13.csv` and confirm:
- No two rows share the same `(sport, game_date, home_team, away_team, value_side)`
- All `position_id` values are real strings (not `NA`)
- Row count matches roughly what the console printed

---

## What We Preserved

The archived logs in `logs/archive/` are not deleted — just moved. If you ever  
want to revisit those days for backtesting once we have a longer track record,  
the raw data is still there.

---

## Going Forward: Weekly Review Checklist

Run this review every Sunday (or after any day with unusual results):

1. Open `paper_trading_log.csv` — check daily ROI trend
2. Open most recent `bet_log_*.csv` — confirm no NA position_ids, no duplicate rows
3. Check settled W/L by sport and odds bucket (expect dogs to lose frequently — that's normal)
4. Spot-check 3–5 settled rows: verify `pnl = (bet_ml−1) × scaled_kelly` for wins, `pnl = −scaled_kelly` for losses
5. Look for any `⚠️ Both sides show value` bets — these need manual review before placing
6. Note any new name mismatch warnings in console output — add to crosswalk immediately

---

*Generated: 2026-03-13 | SureBet v1*
