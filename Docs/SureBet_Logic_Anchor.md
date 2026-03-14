# SureBet Logic Anchor — Source of Truth

*Generated from live codebase. Update this file when core formulas change.*

\---

## 1\. System Constants (tunable — current values)

```r
EV\\\_GATE       <- 0.0524   # minimum EV to flag a bet (5.24%)
EV\\\_CAP        <- 2.00     # sanity ceiling — rejects data errors
BANKROLL\\\_CAP  <- 0.20     # max combined raw Kelly exposure (20%)
# Daily hard cap applied post-scaling via cap\\\_daily\\\_bets(): 10%

# Pythagorean exponents
PYTH\\\_EXP\\\_NBA      <- 14.3    # Morey (PythagenPat)
PYTH\\\_EXP\\\_NCAAB\\\_K  <-  0.287  # dynamic: exp = pts\\\_pg^K
PYTH\\\_EXP\\\_NHL\\\_K    <-  0.458  # dynamic: exp = goals\\\_pg^K
PYTH\\\_EXP\\\_MLB      <-  0.287  # Pythagenpat
PYTH\\\_EXP\\\_MLB\\\_BSR  <-  0.285  # BaseRuns Pythagorean

# Soccer Pythagorean exponents (per league)
PYTH\\\_SOCCER\\\_EPL <- 1.30;  PYTH\\\_SOCCER\\\_BUND <- 1.28
PYTH\\\_SOCCER\\\_SERA <- 1.28; PYTH\\\_SOCCER\\\_LIGA <- 1.30
PYTH\\\_SOCCER\\\_LIG1 <- 1.28; PYTH\\\_SOCCER\\\_MLS  <- 1.25
PYTH\\\_SOCCER\\\_UCL  <- 1.32; PYTH\\\_SOCCER\\\_UEL  <- 1.30

# Spread/total model parameters
K\\\_SPREAD\\\_NBA <- 7.0; K\\\_SPREAD\\\_NCAAB <- 6.5; K\\\_SPREAD\\\_NHL <- 3.2
LEAGUE\\\_AVG\\\_NBA <- 112.5; LEAGUE\\\_AVG\\\_NCAAB <- 75.0; LEAGUE\\\_AVG\\\_NHL <- 3.1
MLB\\\_SIGMA <- 2.5   # normal CDF sigma for MLB totals model
HFA\\\_MLB   <- 0.025 # home field advantage (2.5%)
```

\---

## 2\. Core Formulas

### Pythagorean Win Probability

```r
# NBA (fixed exponent)
pyth\\\_prob = pts\\\_for^14.3 / (pts\\\_for^14.3 + pts\\\_against^14.3)

# NCAAB / MLB (dynamic exponent — Pythagenpat)
exp = (pts\\\_for + pts\\\_against) / games\\\_played ^ 0.287
pyth\\\_prob = pts\\\_for^exp / (pts\\\_for^exp + pts\\\_against^exp)

# NHL (PythagenPuck)
exp = goals\\\_pg ^ 0.458
pyth\\\_prob = goals\\\_for^exp / (goals\\\_for^exp + goals\\\_against^exp)

# Soccer (3-outcome)
raw\\\_home = home\\\_pyth / (home\\\_pyth + away\\\_pyth)
model\\\_home\\\_prob = raw\\\_home \\\* (1 - draw\\\_rate)
model\\\_draw\\\_prob = draw\\\_rate
model\\\_away\\\_prob = (1 - raw\\\_home) \\\* (1 - draw\\\_rate)
```

### MLB Blended Model (BaseRuns + Pythagorean)

```r
bsr\\\_weight = case\\\_when(
  games\\\_played < 40  \\\~ 0.70,   # early season: max BaseRuns weight
  games\\\_played > 100 \\\~ 0.30,   # late season: max Pythagorean weight
  TRUE \\\~ linear interpolation
)
blended\\\_winpct = bsr\\\_weight \\\* baseruns\\\_winpct + (1 - bsr\\\_weight) \\\* pyth\\\_winpct
home\\\_h2h\\\_prob  = home\\\_adj / (home\\\_adj + away\\\_adj)   # where adj = blended \\\* (1 ± HFA\\\_MLB)
```

### Tennis Elo Win Probability

```r
elo\\\_diff        = home\\\_elo - away\\\_elo + 25   # +25 = HFA adjustment
model\\\_home\\\_prob = 1 / (1 + 10^(-elo\\\_diff / 400))
# Surface routing: sport\\\_key → h\\\_elo (hard) | c\\\_elo (clay) | g\\\_elo (grass)
```

### No-Vig Implied Probability (2-way)

```r
overround      = 1/home\\\_ml + 1/away\\\_ml
home\\\_novigprob = (1/home\\\_ml) / overround
away\\\_novigprob = (1/away\\\_ml) / overround
```

### No-Vig Implied Probability (3-way soccer)

```r
overround      = 1/home\\\_ml + 1/draw\\\_ml + 1/away\\\_ml
home\\\_novigprob = (1/home\\\_ml) / overround
draw\\\_novigprob = (1/draw\\\_ml) / overround
away\\\_novigprob = (1/away\\\_ml) / overround
```

### Expected Value

```r
home\\\_ev = model\\\_home\\\_prob \\\* home\\\_ml - 1
away\\\_ev = model\\\_away\\\_prob \\\* away\\\_ml - 1
# 2-gate filter: bet\\\_ev > EV\\\_GATE (0.0524) AND bet\\\_ev <= EV\\\_CAP (2.00) AND edge > 0
```

### Kelly Sizing

```r
# Full Kelly
kelly\\\_full = ((ml - 1) \\\* win\\\_prob - (1 - win\\\_prob)) / (ml - 1)

# Quarter Kelly (always used)
raw\\\_kelly = pmax(kelly\\\_full, 0) / 4

# Global portfolio scaling
sf\\\_combined = min(1, BANKROLL\\\_CAP / sum(all\\\_raw\\\_kelly))
scaled\\\_kelly = raw\\\_kelly \\\* sf\\\_combined

# Daily hard cap (cap\\\_daily\\\_bets)
hard\\\_cap   = bankroll \\\* 0.10
final\\\_risk = scaled\\\_kelly \\\* bankroll   # trimmed at hard\\\_cap by cumsum logic
```

### Expected Spread

```r
calc\\\_expected\\\_spread <- function(win\\\_prob, k = 7.0) {
  log(win\\\_prob / (1 - win\\\_prob)) \\\* k   # log-odds × sport-specific k
}
# k: NBA=7.0, NCAAB=6.5, NHL=3.2
```

### Expected Total (two-method average)

```r
# Method 1: points-based
etot1 = ((apf1 + apa1) \\\* (apf2 + apa2)) / (league\\\_avg \\\* 2)

# Method 2: pace/rating-based (NBA only)
avg\\\_pace = (pace1 + pace2) / 2
etot2    = (((or1 + dr2) / 100 \\\* avg\\\_pace) + ((or2 + dr1) / 100 \\\* avg\\\_pace)) / 2

# Final: average of both methods when pace data available
```

\---

## 3\. Core Function Templates

### make\_position\_id

```r
make\\\_position\\\_id(sport, game\\\_date, home\\\_team, away\\\_team, value\\\_side, bookmaker\\\_key)
# Returns: "sport|game\\\_date|home\\\_team|away\\\_team|value\\\_side|bookmaker\\\_key"
```

### calc\_value\_bets (NBA / NCAAB / NHL)

```r
calc\\\_value\\\_bets(games\\\_df, pyth\\\_home\\\_col, pyth\\\_away\\\_col, sport\\\_label)
# Inputs:  enriched games df with home\\\_ml, away\\\_ml, pyth columns
# Outputs: tibble with home\\\_ev, away\\\_ev, home\\\_edge, away\\\_edge,
#          home\\\_value, away\\\_value flags, home\\\_kelly\\\_q, away\\\_kelly\\\_q
```

### calc\_soccer\_value\_bets

```r
calc\\\_soccer\\\_value\\\_bets(soccer\\\_games\\\_df)
# Inputs:  soccer\\\_games with home\\\_ml, draw\\\_ml, away\\\_ml, model\\\_\\\*\\\_prob
# Outputs: long tibble, one row per value side (home/draw/away)
```

### calc\_tennis\_value

```r
calc\\\_tennis\\\_value(best\\\_odds\\\_df, elo\\\_df, tour\\\_label)
# Inputs:  best\\\_odds\\\_df (game\\\_date, sport\\\_key, home\\\_team, away\\\_team,
#          best\\\_home\\\_ml, best\\\_away\\\_ml), elo\\\_df (player, h\\\_elo, c\\\_elo, g\\\_elo)
# Outputs: tibble with home\\\_elo, away\\\_elo, elo\\\_diff, model\\\_home\\\_prob,
#          home\\\_ev, away\\\_ev, home\\\_kelly\\\_q, away\\\_kelly\\\_q
```

### cap\_daily\_bets

```r
cap\\\_daily\\\_bets(picks\\\_df, bankroll = 1000, cap\\\_pct = 0.10)
# Inputs:  all\\\_picks\\\_df (unified post-scaling df with bet\\\_ev, scaled\\\_kelly)
# Outputs: capped df with final\\\_risk column; hard stop at bankroll \\\* cap\\\_pct
# Logic:   sort desc(bet\\\_ev\\\_pct) → cumsum(risk\\\_dollar) → trim at hard\\\_cap
```

### settle\_paper\_day

```r
settle\\\_paper\\\_day(ml\\\_log\\\_path, bankroll\\\_at\\\_open,
                 st\\\_log\\\_path = NULL,
                 log\\\_date\\\_override = NULL,
                 soccer\\\_pnl\\\_by\\\_date\\\_arg = NULL)
# Returns one-row tibble: date, starting\\\_bankroll, total\\\_risked,
#         settled\\\_pnl\\\_kelly, settled\\\_pnl\\\_dollar, ending\\\_bankroll,
#         daily\\\_roi, cumulative\\\_roi, wins, losses, unsettled
```

\---

## 4\. Data Contracts

### Standard value bet output columns (all sports)

```
sport, game\\\_date, open\\\_time, home\\\_team, away\\\_team, bookmaker\\\_key,
value\\\_side, bet\\\_team, bet\\\_ml, bet\\\_ev, bet\\\_edge, implied\\\_prob,
raw\\\_kelly, scaled\\\_kelly,
position\\\_id, status, placed\\\_time, game\\\_start, settle\\\_time,
stake, result, cashout\\\_value,
hedge\\\_time, hedge\\\_book, hedge\\\_ml, hedge\\\_stake, hedge\\\_result,
clv\\\_at\\\_action, pnl
```

### Position lifecycle states

```
IDENTIFIED → OPEN → LIVE → HEDGED → SETTLED (terminal)
                         → CLOSED  (terminal — cashout)
             → EXPIRED (terminal — never placed)
             → VOID    (terminal — cancelled)
```

### Log file naming

```
logs/bet\\\_log\\\_YYYY-MM-DD.csv             # ML bets (NBA/NCAAB/NHL)
logs/spread\\\_total\\\_log\\\_YYYY-MM-DD.csv    # spreads + totals
logs/soccer\\\_bet\\\_log\\\_YYYY-MM-DD.csv      # soccer 3-way
logs/tennis\\\_bet\\\_log\\\_YYYY-MM-DD.csv      # ATP + WTA
logs/challenger\\\_picks\\\_YYYY-MM-DD.csv    # ATP Challenger
logs/mlb\\\_bet\\\_log\\\_YYYY-MM-DD.csv         # MLB
logs/daily\\\_picks\\\_YYYY-MM-DD.csv         # post-cap unified
logs/paper\\\_trading\\\_log.csv              # cumulative paper P\\\&L
```

\---

## 5\. Sports Coverage \& Status

|Sport|Model|Status|
|-|-|-|
|NBA|PythagenPat 14.3 + pace/ratings|✅ Full (ML/S/T)|
|NCAAB|PythagenPat dynamic (k=0.287)|✅ Full (ML/S/T)|
|NHL|PythagenPuck dynamic (k=0.458)|✅ Full (ML/S/T)|
|Soccer (8 leagues)|Pythagorean + dynamic draw rate|✅ 3-way ML|
|MLB|Pythagenpat + BaseRuns blend|⚠️ Preseason (flip Mar 27)|
|ATP/WTA Tennis|Elo (surface-weighted)|✅ ML only|
|ATP Challenger|Sackmann model + Elo verify|✅ ML only|
|WNBA|Placeholder|🔲 Copy NBA when ready|
|NFL|Placeholder|🔲 Copy NBA (S/T focus)|
|NCAAF|Placeholder|🔲 Copy NCAAB|

\---

## 6\. Upcoming Work (Parking Lot)

* Tennis settler (mirror soccer settler pattern)
* TENNIS\_NAME\_MAP for TOA → Elo name mismatches
* MLB wired into settle\_paper\_day (March 27)
* Stage 2 frontend: JSON exports → static HTML dashboard → hosted → PWA

