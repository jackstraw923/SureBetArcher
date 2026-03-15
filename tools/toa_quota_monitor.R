# ============================================================
# toa_quota_monitor.R — The Odds API Request Tracker
# ============================================================
# Tracks API usage against your monthly quota, logs every
# request with timestamp and endpoint, and warns when
# approaching tier limits.
#
# Usage:
#   source("tools/toa_quota_monitor.R")          # load functions
#   toa_log_request("odds_fetch", n_sports = 13) # call after each fetch
#   toa_quota_report()                           # print status
#
# Called automatically at end of SureBet.R daily run.
# Also used by any future intraday polling scheduler.
#
# TOA Tier: $30/mo — 20,000 requests/month
# Each toa_sports_odds() call = 1 request per sport key
# ============================================================

source("tools/surebet_utils.R")

# ── Constants ─────────────────────────────────────────────────────────────────
TOA_MONTHLY_LIMIT  <- 20000L          # $30/mo tier
TOA_WARN_THRESHOLD <- 0.80            # warn at 80% used
TOA_QUOTA_PATH     <- file.path(REPORTS_DIR, "toa_quota_log.csv")

# ── Schema ────────────────────────────────────────────────────────────────────
# One row per API call batch:
#   timestamp     — when the call was made (ET local)
#   run_date      — date of the run
#   call_type     — "odds_fetch" | "sports_list" | "scores" | "historical" | other
#   n_requests    — number of requests consumed (1 per sport key in odds_fetch)
#   sports        — comma-separated sport keys fetched (if applicable)
#   notes         — freeform context (e.g. "daily run", "intraday poll 1")

# ── Initialize quota log ──────────────────────────────────────────────────────
toa_quota_init <- function() {
  if (!file.exists(TOA_QUOTA_PATH)) {
    tibble(
      timestamp   = as.character(character()),
      run_date    = as.Date(character()),
      call_type   = character(),
      n_requests  = integer(),
      sports      = character(),
      notes       = character()
    ) %>% write_csv(TOA_QUOTA_PATH)
    cat("TOA quota log initialized →", TOA_QUOTA_PATH, "\n")
  }
}

# ── Log a request batch ───────────────────────────────────────────────────────
#' @param call_type  Type of API call
#' @param n_requests Number of requests consumed
#' @param sports     Character vector of sport keys (optional)
#' @param notes      Freeform context string (optional)
toa_log_request <- function(call_type = "odds_fetch",
                            n_requests = 1L,
                            sports     = character(),
                            notes      = "") {
  toa_quota_init()

  new_row <- tibble(
    timestamp  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    run_date   = Sys.Date(),
    call_type  = call_type,
    n_requests = as.integer(n_requests),
    sports     = paste(sports, collapse = ","),
    notes      = notes
  )

  existing <- read_csv(TOA_QUOTA_PATH,
                       col_types = cols(
                         timestamp  = col_character(),
                         run_date   = col_date(),
                         call_type  = col_character(),
                         n_requests = col_integer(),
                         sports     = col_character(),
                         notes      = col_character()
                       ),
                       show_col_types = FALSE)

  bind_rows(existing, new_row) %>%
    write_csv(TOA_QUOTA_PATH)
}

# ── Quota report ──────────────────────────────────────────────────────────────
#' Print current usage vs. tier limit with warnings
#' Uses toa_requests() for authoritative TOA counts, local log for breakdown
toa_quota_report <- function() {
  toa_quota_init()

  # ── Authoritative count from TOA API (costs 0 requests) ──────────────────
  toa_live <- tryCatch({
    toa_requests()
  }, error = function(e) {
    message("⚠️  toa_requests() failed: ", e$message, " — falling back to local log")
    NULL
  })

  log <- read_csv(TOA_QUOTA_PATH,
                  col_types = cols(
                    run_date   = col_date(),
                    n_requests = col_integer(),
                    .default   = col_character()
                  ),
                  show_col_types = FALSE)

  today      <- Sys.Date()
  month_start <- floor_date(today, "month")

  # Use TOA live count if available, else fall back to local log sum
  if (!is.null(toa_live) && nrow(toa_live) > 0) {
    month_used <- as.integer(toa_live$requests_used[1])
    remaining  <- as.integer(toa_live$requests_remaining[1])
    source_label <- "TOA API (authoritative)"
  } else {
    month_log  <- log %>% filter(run_date >= month_start)
    month_used <- sum(month_log$n_requests, na.rm = TRUE)
    remaining  <- TOA_MONTHLY_LIMIT - month_used
    source_label <- "local log (fallback)"
  }

  month_pct <- month_used / TOA_MONTHLY_LIMIT * 100

  # Today's usage from local log (TOA doesn't break down by day)
  today_log  <- log %>% filter(run_date == today)
  today_used <- sum(today_log$n_requests, na.rm = TRUE)

  # Days remaining in month
  days_in_month    <- days_in_month(today)
  day_of_month     <- day(today)
  days_remaining   <- days_in_month - day_of_month + 1
  daily_budget_rem <- if (days_remaining > 0)
    floor(remaining / days_remaining) else 0L

  cat("\n────────────────────────────────────────────────────────────\n")
  cat("TOA API Quota Status\n")
  cat("────────────────────────────────────────────────────────────\n")
  cat(sprintf("Source:            %s\n", source_label))
  cat(sprintf("Tier:              $30/mo — %s requests/month\n",
              formatC(TOA_MONTHLY_LIMIT, format = "d", big.mark = ",")))
  cat(sprintf("Month-to-date:     %s used / %s total (%.1f%%)\n",
              formatC(month_used, format = "d", big.mark = ","),
              formatC(TOA_MONTHLY_LIMIT, format = "d", big.mark = ","),
              month_pct))
  cat(sprintf("Remaining:         %s requests\n",
              formatC(remaining, format = "d", big.mark = ",")))
  cat(sprintf("Today's usage:     %d requests (local log)\n", today_used))
  cat(sprintf("Days remaining:    %d days | Daily budget: %d requests/day\n",
              days_remaining, daily_budget_rem))

  # Warning thresholds
  if (month_pct >= 95) {
    cat("⛔ CRITICAL: >95% of monthly quota used — pause non-essential calls\n")
  } else if (month_pct >= TOA_WARN_THRESHOLD * 100) {
    cat(sprintf("⚠️  WARNING: %.0f%% of monthly quota used\n", month_pct))
  } else {
    cat("✅ Quota healthy\n")
  }

  # Usage breakdown by call type (from local log — TOA doesn't provide this)
  if (nrow(log) > 0) {
    month_log <- log %>% filter(run_date >= month_start)
    if (nrow(month_log) > 0) {
      cat("\nBreakdown by call type (this month — local log):\n")
      month_log %>%
        group_by(call_type) %>%
        summarise(requests = sum(n_requests, na.rm = TRUE),
                  calls    = n(),
                  .groups  = "drop") %>%
        arrange(desc(requests)) %>%
        print()
    }
  }

  # Daily trend (last 7 days)
  if (nrow(log) > 1) {
    recent <- log %>%
      filter(run_date >= today - 6) %>%
      group_by(run_date) %>%
      summarise(daily_requests = sum(n_requests, na.rm = TRUE), .groups = "drop") %>%
      arrange(run_date)

    if (nrow(recent) > 1) {
      cat("\nDaily usage (last 7 days — local log):\n")
      print(recent)
    }
  }

  cat("────────────────────────────────────────────────────────────\n\n")

  invisible(list(
    month_used      = month_used,
    month_pct       = month_pct,
    remaining       = remaining,
    today_used      = today_used,
    days_remaining  = days_remaining,
    daily_budget    = daily_budget_rem
  ))
}

# ── Intraday poll budget calculator ──────────────────────────────────────────
#' Given how many sports you want to poll, how many times per day can you poll?
#' @param n_sports     Number of sport keys per poll cycle
#' @param safety_pct   Reserve this % of daily budget as buffer (default 20%)
toa_poll_budget <- function(n_sports = 13L, safety_pct = 0.20) {
  toa_quota_init()

  # Try live count first
  toa_live <- tryCatch(toa_requests(), error = function(e) NULL)

  if (!is.null(toa_live) && nrow(toa_live) > 0) {
    requests_left <- as.integer(toa_live$requests_remaining[1])
  } else {
    # Fall back to local log
    log <- read_csv(TOA_QUOTA_PATH,
                    col_types = cols(run_date = col_date(),
                                     n_requests = col_integer(),
                                     .default = col_character()),
                    show_col_types = FALSE)
    month_start   <- floor_date(Sys.Date(), "month")
    month_used    <- sum(log$n_requests[log$run_date >= month_start], na.rm = TRUE)
    requests_left <- TOA_MONTHLY_LIMIT - month_used
  }

  today           <- Sys.Date()
  days_remaining  <- days_in_month(today) - day(today) + 1
  daily_budget    <- floor(requests_left / days_remaining)
  usable_budget   <- floor(daily_budget * (1 - safety_pct))
  polls_possible  <- floor(usable_budget / n_sports)

  cat(sprintf(
    "\n📡 Intraday Poll Budget\n  %d sports/poll | %s requests left this month\n",
    n_sports, formatC(requests_left, format = "d", big.mark = ",")))
  cat(sprintf(
    "  Daily budget: %d requests | Usable (%.0f%% safety): %d\n",
    daily_budget, (1 - safety_pct) * 100, usable_budget))
  cat(sprintf(
    "  Max polls today: %d (every ~%.0f minutes if spread evenly)\n\n",
    polls_possible,
    ifelse(polls_possible > 0, 24 * 60 / polls_possible, Inf)
  ))

  invisible(polls_possible)
}
