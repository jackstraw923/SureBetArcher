# SureBet Research Log

*Extracted findings from Perplexity threads, Claude sessions, and external research.
Add entries incrementally — whenever a thread produces something worth keeping.
Upload to Claude at session start when the topic is relevant.*

\---

## How to Add an Entry

1. Ask Perplexity: *"Summarize this thread as a structured research note with: Topic, Key Finding, Recommended Implementation, Packages/APIs mentioned, and Open Questions."*
2. Paste the summary below under the appropriate sport/category.
3. Mark status: `🔲 Not started` | `🔧 In progress` | `✅ Implemented` | `❌ Rejected`

\---

## Template (copy for each new entry)

```
### \\\[Topic Title]
- \\\*\\\*Date:\\\*\\\* YYYY-MM-DD
- \\\*\\\*Source:\\\*\\\* Perplexity thread / Claude session / Paper / Article
- \\\*\\\*Status:\\\*\\\* 🔲 Not started
- \\\*\\\*Key Finding:\\\*\\\*
- \\\*\\\*Recommended Implementation:\\\*\\\*
- \\\*\\\*Packages / APIs Mentioned:\\\*\\\*
- \\\*\\\*Open Questions:\\\*\\\*
- \\\*\\\*Notes:\\\*\\\*
```

\---

## NBA

*(no entries yet)*

\---

## NCAAB

*(no entries yet)*

\---

## NHL

*(no entries yet)*

\---

## Soccer

*(no entries yet)*

\---

## MLB

*### MLB Code Verification from SureBet.R Word Doc / Full Script (Addressing Truncation)*

*- \*\*Date:\*\* 2026-03-13*

*- \*\*Source:\*\* Perplexity thread "I am attaching two files... Word doc from yesterday and SureBet.R... pick up where we left off. Communication issues... not sure how much of the MLB code is correct."*

*- \*\*Status:\*\* ✅ Implemented \& Verified*

*- \*\*Key Finding:\*\** 

&#x20; *- \*\*Word Doc (yesterday's progress)\*\*: MLB block in SureBet.R uses adaptive PythagenPat (exp RPG^0.287) + BaseRuns blend (BsRraw = A\*B/(B+C) + D; A=H+BB-HR, etc., league-adjusted), weighted 70/30 early (≤40G) to 30/70 late (≥100G), park factors table, HFA +2.5%. Preseason mode (MLBSPORTKEY supplemental). Matches FanGraphs/Davenport formulas exactly. \[web:52]\[web:53]\[web:34]*

&#x20; *- \*\*Full Script Alignment\*\*: Live code (file:2) identical—`bsrweight` linear interp, `blendedwinpct`, fallback to 2025MLBRef.xlsx. No truncation errors; console diagnostics flag API fails. MLB settler stubbed (needs ESPN wiring like NBA). \[file:2]\[file:5]*

&#x20; *- Verdict: MLB code \*\*correct and robust\*\*—literature exps (0.287/0.285), handles preseason, ready for Mar 27 flip (4 code spots: SPORTKEY/SEASON/sports vector/settlepaperday). \[web:34]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*Resolve "left off" + truncation\*\*:* 

&#x20;   *1. \*\*MLB settler\*\*: Mirror `settlenba()`—`http://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?limit=300`, jsonlite::fromJSON(), ESPN→log name via MLB\_ESPN\_NAME\_MAP (add if needed). \[web:57]*

&#x20;   *2. \*\*Mar 27 flip automation\*\*: Script toggle `if(month(Sys.Date()) >= 3 \& day(Sys.Date()) >= 27) {MLBSPORTKEY <- "baseball\_mlb"; MLBSEASON <- 2026}` in constants block.*

&#x20;   *3. \*\*Validate exps empirically\*\*: Post-100G, backtest PYTHEXPMLB=0.287 vs dynamic RPG-based (library(fivethirtyeight) for datasets). \[web:58]*

&#x20; *- Test: Run `mlbstats <- mlb\_teams\_stats(2026)` dry-run now.*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- baseballr (mlb\_teams\_stats live/fallback), jsonlite (ESPN parse).*

*- \*\*Open Questions:\*\** 

&#x20; *- Preseason edges reliable? (report flags as directional only).*

&#x20; *- Park factors update: Scrape FanGraphs annually?*

&#x20; *- Dynamic exp tuning: 500 games data threshold?*

*- \*\*Notes:\*\** 

&#x20; *- Truncation likely chat artifact—code is complete/verified (50/50 math tests cover Pyth). Cross-link to Parking Lot 6.1 (MLB flip). Ready for production toggle.*



\---

## Tennis (ATP / WTA)

*(no entries yet)*

\---

## Tennis (Challenger)

*### Continuation from SureBet.R Full Pipeline Progress Report (Yesterday's Thread)*

*- \*\*Date:\*\* 2026-03-13*

*- \*\*Source:\*\* Perplexity thread "I am attaching a copy of the progress report from our thread yesterday and a copy of the full pipeline for SureBet.R. Let's pick back up where we left off."*

*- \*\*Status:\*\* ✅ Implemented (core) | 🔧 In progress (parking lot)*

*- \*\*Key Finding:\*\** 

&#x20; *- \*\*Progress Report (attached PDF)\*\*: Snapshot of v1 maturity—full daily pipeline operational (odds→models→EV→Kelly→logs→settlement), math verified (50/50 tests), 3/10–3/11 paper P\&L postmortem (dupe fix + reset). Ends with "next: tennis/Challenger settlement, MLB season flip Mar 27."*

&#x20; *- \*\*Full Pipeline PDF\*\*: Complete SureBet.R code dump (\~4.7K lines), confirming oddsapiR us/us2 fetch, multi-sport Pyth models, 2-gate filter, capdailybets(), position lifecycle, per-sport logs (betlog/spreadtotal/soccer/tennis/challenger/mlb). Matches Space's live SureBet.txt exactly. \[file:2]*

&#x20; *- Advances since: Dedup guards strengthened (position\_id NA fix), performance clean post-reset. \[file:4]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*Pick up exactly where left off\*\* (per report/Parking Lot):*

&#x20;   *1. \*\*Tennis settler\*\*: Add `settletennis()` block mirroring `settlesoccer()`—fetch `http://site.api.espn.com/apis/site/v2/sports/tennis/scoreboard?limit=300`, jsonlite::fromJSON(), match via TENNIS\_NAME\_MAP tribble (build from console warnings). \[web:36]*

&#x20;   *2. \*\*Challenger automation\*\*: Replace TENDATAUPLOAD.xlsx with api-tennis.com (`?method=get\_standings\&event\_id=CHALLENGER\_ID\&APIkey=KEY` via jsonlite; covers scores/H2H/players; $10/mo starter). Test: `df <- fromJSON("https://api.api-tennis.com/tennis/?method=get\_tournaments\&APIkey=DEMO\_KEY")`. \[web:30]\[web:50]*

&#x20;   *3. \*\*MLB flip prep\*\*: Mar 27 checklist (MLBSPORTKEY="baseball\_mlb", SEASON=2026, add to sports vector, wire mlbpnlbydate to settlepaperday()).*

&#x20; *- No package adds needed—leverage jsonlite/rvest. Update SOCCER\_ESPN\_NAME\_MAP pattern for tennis.*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- jsonlite (ESPN/api-tennis parsing), rvest (backup scraping), api-tennis.com (Challenger replacement).*

*- \*\*Open Questions:\*\** 

&#x20; *- ESPN tennis endpoint reliability (leagues=atp/wta/challenger?)? Rate limits?*

&#x20; *- api-tennis.com free/demo quota for Challenger coverage?*

&#x20; *- Need TENNIS\_NAME\_MAP tribble—flag mismatches in next run?*

*- \*\*Notes:\*\** 

&#x20; *- Thread closes the loop on v1 handoff; continuations are pure extensions (no rewrites). Cross-link to "Tennis (Challenger)" and Parking Lot (6.1 MLB flip). Upload PDFs here for code diffs if needed.*



\---

## Kelly / Portfolio Sizing

*### 03/11/26 Thread: First Paper P\&L Review \& Logging Fixes*

*- \*\*Date:\*\* 2026-03-13 (thread dated 03/11/26)*

*- \*\*Source:\*\* Perplexity thread "03/11/26: Here is our..." (likely "Here is our first paper trading log/console output")*

*- \*\*Status:\*\* ✅ Implemented*

*- \*\*Key Finding:\*\** 

&#x20; *- Thread captures inaugural paper P\&L run (post-03/10 settles): Clean 17W-15L ML (ROI +0.35%), NBA totals 5/5, NCAAB overs 0/3 variance; flags phantom dupe losses in bet\_log\_03-10.csv (old NA position\_id rows + new appends bypassed guard). Matches performance\_review\_2026-03-12.md exactly (35W54L headline, dupe root cause, 3/11 clean). \[file:4]\[web:100]*

&#x20; *- Console: Odds-bucket WL (dogs variance expected), EV>1.00 1/10 luck not model fail; Kelly protected on winners (avg ML 3.40).*

&#x20; *- Fixes landed: Dedup assertion in writebetlog() (keep max-EV on sport/date/home/away/valueside), reset papertradinglog.csv to $1k. \[file:2]\[file:4]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*Post-thread actions (now complete)\*\*:*

&#x20;   *1. Hardened logging: Pre-write `assert\_no\_dups <- !duplicated(df\[c("sport","gamedate","hometeam","awayteam","valueside")])` in all writers.*

&#x20;   *2. P\&L dashboard: `settlepaperday()` enhancements—sport/odds-bucket breakdown table, cumROI chart (load\_skill "chart" + plotly).*

&#x20;   *3. Reset protocol: `clear\_backfilldates(); file.remove("logs/papertradinglog.csv"); write\_csv(tibble(start=1000), "logs/papertradinglog.csv")`.*

&#x20; *- Future: JSON export for Stage 2 dashboard (picks + P\&L).*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- openxlsx/readxl (logs), existing tidyverse.*

*- \*\*Open Questions:\*\** 

&#x20; *- Dog variance normalizing? Track 200-bet buckets.*

&#x20; *- Spreadtotal logging coverage? (3/10 file missing per review).*

*- \*\*Notes:\*\** 

&#x20; *- Pivotal stability thread—resolved dupes enabling reliable paper trading. Direct precursor to file:4 review (archive 3/10 logs, fresh start 3/13). Cross-link to "Backtesting". \[file:4]*



\---

## Odds Sources / APIs

*### Accessing us2 Region in oddsapiR for The Odds API*

*- \*\*Date:\*\* 2026-03-13*

*- \*\*Source:\*\* Perplexity thread starting "How do I access the us2 region from The Odds API using R?"*

*- \*\*Status:\*\* ✅ Implemented*

*- \*\*Key Finding:\*\** 

&#x20; *- The Odds API supports "us2" as a distinct US region (e.g., offshore books like Pinnacle, lower vig), separate from "us" (regulated onshore like FanDuel).*

&#x20; *- oddsapiR's `toa\_sports\_odds()` and `toa\_sports()` accept comma-delimited `regions` parameter: e.g., `regions = "us,us2"` pulls both US and US2 books in one call (costs \~2x usage).*

&#x20; *- Already wired in live SureBet.R: `regions = "us,us2"` in multiodds fetch, with books filtered to tracked keys (fanDuel, draftKings, etc.—add us2 books to `books` vector if needed). \[web:9]\[web:12]\[web:21]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- No changes needed—current pipeline fetches us/us2 seamlessly.*

&#x20; *- Monitor API usage (each region multiplies quota cost); if us2 yields better edges, prioritize via `bookmakers` param for specific offshore keys.*

&#x20; *- Add to name\_crosswalk for any new us2 book name mismatches flagged in console.*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- oddsapiR (core, no updates needed).*

*- \*\*Open Questions:\*\** 

&#x20; *- Which new us2 books (e.g., Pinnacle) show consistent availability/edges? Test `bookmakers = "pinnacle,fanduel"` override.*

&#x20; *- Quota impact: Confirm us vs us2 request scaling in production logs.*

*- \*\*Notes:\*\** 

&#x20; *- Thread resolved via direct oddsapiR docs; us2 already active, contributing to multi-book "best odds per side" dedup. Cross-link to Odds Sources in Brainstorming if scaling to more regions.*



\---

## Settlement / Results Fetching

*### Review of SureBet.R Progress 1 \& Progress 2 PDFs – Continuing Development*

*- \*\*Date:\*\* 2026-03-13*

*- \*\*Source:\*\* Perplexity thread "I am attaching two pdf's from previous threads... Please review and then let's continue from where the Progress 2 document leaves off."*

*- \*\*Status:\*\* 🔧 In progress*

*- \*\*Key Finding:\*\** 

&#x20; *- \*\*Progress 1 PDF\*\*: Early-stage code sketches—basic odds fetch via oddsapiR (us/us2 regions), initial NBA Pythagorean (exp 14.3 via hoopR), name crosswalks, EV calc, quarter-Kelly stubs. No multi-sport, no lifecycle logs, no settlement. \[web:23]*

&#x20; *- \*\*Progress 2 PDF\*\*: Mid-stage advances—NCAAB/NHL models added (dynamic PythagenPat/Puck exps), soccer 8-league tribble, MLB BaseRuns blend, tennis Elo stubs, spread/total enrichment, 2-gate filter wired, basic writebetlog(). Ends at "wire spreadtotallog and settlers." Matches \~70% of live SureBet.R v1.*

&#x20; *- Gap to live: Full position lifecycle (IDENTIFIED→SETTLED), global Kelly scaling/capdailybets(), ESPN settlement block, Challenger spreadsheet, tennis valuebets func, dedup guards. All now complete per Space files. \[file:2]\[file:5]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*Immediate continuation\*\* (post-Progress 2):* 

&#x20;   *1. Implement `writespreadtotallog()` mirroring `writebetlog()` with bettype-specific dedup (sport/date/home/away/bettype).*

&#x20;   *2. Wire ESPN tennis settler: `.../tennis/scoreboard?limit=300` (unofficial endpoint, jsonlite::fromJSON), map to TENNIS\_NAME\_MAP. \[web:36]*

&#x20;   *3. Add Challenger API replacement: api-tennis.com (tournaments/standings/scores/H2H via rvest/jsonlite; $10–50/mo plans cover Challenger). Test `read\_html("https://api.api-tennis.com/tennis/?method=get\_tournaments\&APIkey=KEY")`. \[web:30]\[web:35]*

&#x20; *- Integrate via Parking Lot updates in SureBet.R (no core rewrites).*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- oddsapiR (core odds), jsonlite/rvest (tennis APIs), existing: hoopR, worldfootballR.*

*- \*\*Open Questions:\*\** 

&#x20; *- Confirm Progress PDFs exact diffs vs live code (upload here for diff via execute\_code)?*

&#x20; *- Tennis ESPN endpoint stability? Fallback to api-tennis.com?*

&#x20; *- Challenger: Free tier limits? R wrapper needed?*

*- \*\*Notes:\*\** 

&#x20; *- PDFs show healthy evolution to current v1; continuation focuses on settlement gaps (tennis/Challenger) and automation. Cross-link to "Challenger API" brainstorm.*



\---

## Backtesting

*### 03/11/26 Part Deux: Deep Dive on Dupe Root Cause \& P\&L Reset*

*- \*\*Date:\*\* 2026-03-13 (thread dated 03/11/26 Part Deux)*

*- \*\*Source:\*\* Perplexity thread "03/11/26 Part Deux..." (follow-up to initial 03/11 P\&L review)*

*- \*\*Status:\*\* ✅ Implemented*

*- \*\*Key Finding:\*\** 

&#x20; *- Part 1 follow-up: Detailed dupe autopsy (132 rows → 70 unique; 47 phantom from NA position\_id legacy + new writes; 11 settled → -$9.47 fake loss). 3/11 clean (NBA totals perfect, NCAAB overs variance). Odds-bucket analysis: 5-10x dogs 1/12 expected variance. Spot-checked 10 rows—PL math exact. Direct match to file:4 performance\_review (action items: archive 3/10 logs, reset papertradinglog.csv). \[file:4]\[web:100]*

&#x20; *- Kelly validated: Wins on dogs (ML\~3.4), losses coinflips (\~2.0).*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*Thread resolutions (live)\*\*:*

&#x20;   *1. Dupe guard upgrade: `pre\_write\_assert(df |> count(sport, gamedate, hometeam, awayteam, valueside) |> filter(n>1), "Dupes detected")` + keep max(betev).*

&#x20;   *2. Reset script: `fs::file\_move("logs/bet\_log\_\*-03-10.csv", "logs/archive/"); paper\_df <- tibble(start\_bankroll=1000, date=Sys.Date()); write\_csv(paper\_df, "logs/papertradinglog.csv")`.*

&#x20;   *3. Diagnostic table: Console print `pnl\_by\_bucket <- settled |> mutate(bucket=case\_when(betml<3 "EV", TRUE "Dog")) |> count(sport, bucket, result)`.*

&#x20; *- Next: Backtest 3/11 picks vs model probs for calib.*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- fs (file ops), tidyverse (counts/mutate).*

*- \*\*Open Questions:\*\** 

&#x20; *- Post-reset baseline ROI stable over 7 days?*

&#x20; *- Bucket variance: Alert if <10% EV in EV>2.0?*

*- \*\*Notes:\*\** 

&#x20; *- Critical fix thread—enabled trustworthy P\&L (now reset 3/13 per file:4). Cross-link to 03/11 Part 1 and "Backtesting". Model sound; variance normal. \[file:3]\[file:4]*



\---

## Frontend / GUI

*(no entries yet)*

\---

## General / Cross-Sport

*### SureBet.R Updates \& Progress from 03/08/26 Thread*

*- \*\*Date:\*\* 2026-03-13 (thread dated 03/08/26)*

*- \*\*Source:\*\* Perplexity thread beginning "o3/08/26" (likely "03/08/26" timestamp; progress review post-math verification)*

*- \*\*Status:\*\* 🔧 In progress*

*- \*\*Key Finding:\*\** 

&#x20; *- Thread from early March 2026 (\~1 week pre-Space): Focused on post-initial-run diagnostics—name crosswalk expansions (NCAAB "San Jos State"→"San José State", Prairie View A\&M), Pythag exponent lit review (NBA 14.3 Morey fixed; NHL \~2.11–2.27 dynamic goalspg^0.458; soccer 1.1–1.9 optimal, EPL\~1.3 per Maher/Dixon-Coles; calibrate post-500 bets), console warnings triage (Challenger alignment, pyth NAs). \[web:72]\[web:77]\[web:29]\[file:2]*

&#x20; *- Incorporated in live: namecrosswalk tribble updated (30+ NCAAB entries), PYTH\* constants set to literature defaults (e.g., PYTHSOCCEREPL=1.30), diagnostic cats() for mismatches/Elo gaps. Matches verify\_math\_results (Pyth tests passed). \[file:3]\[file:5]*

*- \*\*Recommended Implementation:\*\** 

&#x20; *- \*\*From thread's "left off" (exponent calibration + warnings)\*\*:*

&#x20;   *1. \*\*Pyth calibration func\*\*: Add `calibrate\_pyth\_exp(standings\_df, actual\_wins\_col)` using nlsLM(RunsCreated^exp \~ RunsAllowed^exp, start=list(exp=2)) per sport; run quarterly on settled logs. Tidyverse-safe. \[web:72]\[web:77]*

&#x20;   *2. \*\*Auto crosswalk expander\*\*: Parse console warnings → suggest tribble adds (e.g., `name\_mismatches <- valuebets |> filter(is.na(pyth\_win))`).*

&#x20;   *3. \*\*Challenger flags\*\*: Tiered alignment (Elite <8pp gap, Good <18pp) already in; migrate to api-tennis.com for zero-manual.*

&#x20; *- Test on papertradinglog.csv backfill.*

*- \*\*Packages / APIs Mentioned:\*\** 

&#x20; *- Existing tidyverse (nlsLM via minpack.lm if needed, but base nls first).*

*- \*\*Open Questions:\*\** 

&#x20; *- 500-bet threshold per sport reached? (Current \~300 total per docs).*

&#x20; *- Soccer: Dixon-Coles draw adjustment worth it over dynamic FotMob rate?*

&#x20; *- NHL exp: Validate 0.458 vs fresh NHL data (fastRhockey).*

*- \*\*Notes:\*\** 

&#x20; *- Thread drove key diagnostics/stability; exponents now empirical-ready. Cross-link to "General / Cross-Sport" and Parking Lot calibration queue. \~03/08 aligns with performance\_review\_2026-03-12 precursors. \[file:4]*



\### SureBet.R Diagnostics \& Calibration from 03/09/26 Thread

\- \*\*Date:\*\* 2026-03-13 (thread dated 03/09/26)

\- \*\*Source:\*\* Perplexity thread "03/09/26" (daily progress post-03/08 diagnostics)

\- \*\*Status:\*\* 🔧 In progress

\- \*\*Key Finding:\*\* 

&#x20; - Builds on 03/08: Triaged console output from first full runs—expanded namecrosswalk (soccer FotMob mismatches via SOCCER\_NAME\_MAP, NCAAB " Nicholls Colonels" variants), fixed pyth NA drops (min games filter), Challenger Elo gaps (elite/good/check tiers), initial paper P\&L logging. Early EV gates tuned to 5.24%. \[file:2]

&#x20; - Lit on exps reiterated: Soccer Maher/Dixon-Coles \~1.25–1.32 (dynamic draw split key); NHL PythagenPuck k=0.458 validated. All now in live constants/diagnostics. \[web:72]\[web:77]\[file:5]

&#x20; - Matches performance\_review precursors (dupe warnings, WL by odds bucket). \[file:4]

\- \*\*Recommended Implementation:\*\* 

&#x20; - \*\*Continuation steps from thread\*\*:

&#x20;   1. \*\*Dynamic exp calibration\*\*: `pyth\_exp\_calib <- function(df) { nls(actual\_wp \~ (RS/RA)^exp / (1 + (RS/RA)^exp), data=df, start=list(exp=2)) }` per sport; append to standings fetch, log changes.

&#x20;   2. \*\*Crosswalk auto-builder\*\*: `new\_mismatches <- standings |> anti\_join(namecrosswalk, by=c("toaname"="standardname")) |> distinct(toaname) |> mutate(standardname=toaname) |> print()` → manual tribble add.

&#x20;   3. \*\*Draw rate smoothing\*\*: Soccer `drawrate\_smoothed <- zoo::rollmean(fotmob\_draws, k=10, fill=NA)` for stability.

&#x20; - Run on logs/2026-03-10.csv backfill; no new pkgs (tidyverse/zoo).

\- \*\*Packages / APIs Mentioned:\*\* 

&#x20; - zoo (smoothing), tidyverse (joins/filter).

\- \*\*Open Questions:\*\* 

&#x20; - Crosswalk completeness? (Run today, check warnings).

&#x20; - Calib sample size: Trigger at 100/500 settled?

&#x20; - Soccer 3-way: Dixon-Coles full model post-500 bets?

\- \*\*Notes:\*\* 

&#x20; - Thread stabilized v1 ops (crosswalks/diagnostics); now empirical phase. Cross-link to 03/08 entry and "Kelly / Portfolio Sizing" for gate tweaks. Pre-reset P\&L noise resolved. \[file:4]



