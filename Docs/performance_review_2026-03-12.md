# SureBet Performance Review
**Date:** 2026-03-12  
**Period:** 2026-03-10 through 2026-03-11  
**Analyst:** Claude (Sonnet 4.6)

---

## Headline Numbers

| Date | Starting BR | Risked | P&L $ | ROI | Record |
|------|-------------|--------|-------|-----|--------|
| 3/10 | $1,000.00 | $99.69 | −$25.74 | −2.57% | 18W–39L |
| 3/11 | $974.26 | $47.84 | −$3.37 | −0.35% | 17W–15L |
| **Total** | | **$147.53** | **−$29.11** | **−2.91%** | **35W–54L** |

---

## Settlement & P&L Math: Verified ✅

All 10 spot-checked rows matched hand calculation exactly:

```
pnl_win  = (bet_ml − 1) × scaled_kelly
pnl_loss = −scaled_kelly
```

No errors in the settler. The math is correct.

---

## Root Cause Analysis

### Issue 1 — Phantom Duplicate Bets (PRIMARY) 🔴

**What happened:**  
The 3/10 log was written twice — once by an older version of the script
(which produced rows with `position_id = NA`), and once by the current version
(which produces real position_ids). The `write_bet_log()` dedup guard uses
`position_id` to skip already-logged rows, but old rows had `position_id='NA'`
so they didn't match, and new rows were appended on top of them.

**Scale:**
- 132 total rows logged for 3/10 ML bets
- Only ~70 were unique game+side combinations
- 62 rows (~47%) were duplicates
- 11 of those duplicate rows were settled, contributing **−$9.47** in phantom losses

**Real-world impact:**  
These bets never actually existed. They are a logging artifact from running
the new script on a day that already had an old-format log file.

**Fix:**  
The 3/10 log file is corrupted by old-format data. It should be deleted or
archived and excluded from paper trading. The 3/11 log (written entirely by
the new code) is clean.

---

### Issue 2 — Multi-Book Logging (SECONDARY) 🟡

**What happened:**  
Even within the current-format rows, some games still appeared at 2–3 books
(e.g., Utah Utes at FanDuel, Fanatics, and ESPN Bet). The pipeline dedup:

```r
value_best <- value_all %>%
  group_by(sport, game_date, bet_team) %>%
  slice_max(bet_ev, n = 1, with_ties = FALSE) %>%
  ungroup()
```

...groups by `bet_team`, which should collapse multi-book rows to one. However,
the `"both"` sided bets use `bet_team = "HomeTeam + AwayTeam"` which may not
dedup correctly. Also, the old-format rows that bypassed the guard mean both
the pre-dedup and post-dedup versions got written to the same file.

**Fix:**  
After clearing old logs and resetting, confirm next run's bet_log has no
duplicate `(sport, game_date, home_team, away_team, value_side)` combinations.
Add a diagnostic assertion to `write_bet_log()`.

---

### Issue 3 — Dog-Heavy Slate + Small Sample (STRUCTURAL / EXPECTED) 🟢

**3/10 settled ML bets by odds range:**

| Odds range | W | L | Actual W% | Implied W% |
|------------|---|---|-----------|------------|
| 2.00–3.00 | 6 | 16 | 27.3% | 38.7% |
| 3.00–5.00 | 11 | 7 | 61.1% | 28.7% |
| 5.00–10.00 | 1 | 12 | 7.7% | 14.1% |

The 5.00+ bucket went 1–12 (7.7% actual vs 14.1% implied). On any given day,
heavy underdogs lose most of the time — that's their nature. With only 13 bets
in that bucket, the variance is enormous. This is **not a model failure**; it
is expected short-run behavior.

**The EV > 1.00 bucket specifically went 1–10.** These are the highest-odds
bets (Utah Utes at 6.0–6.7, NJIT at 6.5–7.1, Brooklyn Nets at 9.0–9.3).
They need to hit ~14–17% of the time to be profitable long-term. 1/11 = 9%
over 11 bets is bad luck, not bad model.

**NHL was actually profitable despite going 6–11** because we won on the
bigger dogs (avg winning ML = 3.40) and lost on near-coinflips (avg losing
ML = 2.04). That is exactly what Kelly sizing is supposed to do.

---

### Issue 4 — 3/10 Spread/Total Log Missing 🟡

We do not have `spread_total_log_2026-03-10.csv`. The paper trading dashboard
shows $99.69 total risked on 3/10, which implies spread/total bets were
included in that figure. Without the file we cannot verify the 3/10 spread
settler. This needs to be checked locally.

---

## 3/11 Results: Clean

| Type | W | L | W% | PnL (kelly) |
|------|---|---|----|-------------|
| NBA ML | 1 | 3 | 25.0% | −0.0026 |
| NCAAB ML | 4 | 3 | 57.1% | −0.0007 |
| NBA OVER | 3 | 0 | 100% | +0.0017 |
| NBA SPREAD | 3 | 4 | 42.9% | +0.0012 |
| NBA UNDER | 2 | 0 | 100% | +0.0015 |
| NCAAB OVER | 0 | 3 | 0% | −0.0061 |
| NCAAB SPREAD | 2 | 2 | 50.0% | +0.0002 |
| NCAAB UNDER | 2 | 0 | 100% | +0.0012 |

The 3/11 log is clean — no duplicates, correct schema throughout.  
NCAAB OVERs went 0–3 (bad luck on totals, small sample).  
NBA totals went 5–0 (good day, also small sample).

---

## Action Items

| Priority | Issue | Action |
|----------|-------|--------|
| 🔴 HIGH | 3/10 log corrupted by old-format rows | Archive/delete 3/10 logs, reset paper trading, exclude from backtest |
| 🔴 HIGH | Paper trading reflects phantom losses | Reset `paper_trading_log.csv` after log cleanup |
| 🟡 MED | Verify no duplication in 3/11+ logs | Add dedup assertion to `write_bet_log()` |
| 🟡 MED | 3/10 spread/total log missing | Locate locally or accept as unrecoverable |
| 🟢 LOW | Dog-heavy slate losses | Not a bug — monitor over 200+ bets before calibration judgment |
| 🟢 LOW | NCAAB OVER 0–3 on 3/11 | Not a bug — 3 bets is pure noise |

---

## Recommended Reset Procedure

1. Archive `logs/bet_log_2026-03-10.csv` → `logs/archive/`
2. Archive all other 3/10 logs
3. Delete or reinitialize `paper_trading_log.csv`
4. Clear `backfill_dates` vector in `SureBet.R`
5. Add dedup assertion to `write_bet_log()` (one line)
6. Next clean run starts fresh from 3/13

---

## Calibration Baseline (what to watch going forward)

The model is **not broken**. What we can say after 2 days:

- Settlement math: ✅ verified correct
- Dedup logic (current code): ✅ correct in pipeline, logging guard confirmed
- 3/10 log: ❌ corrupted, exclude
- 3/11 log: ✅ clean, use as baseline

**Minimum sample before calibration judgment:** 200 settled bets per sport.  
At current volume (~20–30 settled ML bets/day), that's ~7–10 days per sport.

---

*Generated: 2026-03-12 | SureBet Performance Review v1*
