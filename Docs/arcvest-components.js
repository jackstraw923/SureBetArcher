// ============================================================
// arcvest-components.js
// ArcVest Shared Component Injector
// Mountain Engineering | Mountain Capital, LLC
// Version 1.0 | April 2026
//
// Injects canonical nav and footer HTML into every page.
// Single source of truth — edit here, changes propagate everywhere.
//
// USAGE: Every page includes two placeholder divs and this script:
//   <div id="nav-root"></div>
//   ... page content ...
//   <div id="footer-root"></div>
//   <script src="/arcvest-components.js"></script>
//
// FOOTER VARIANTS:
//   Standard (main content pages):  includes Reset 4 baseline + last-run
//   Minimal  (legal/auth pages):    includes copyright only
//   Set via: <div id="footer-root" data-variant="minimal"></div>
//
// TOURNAMENTS NAV LINK:
//   Injected conditionally after ODDS when summary.json
//   returns tournaments_active = true. Never hardcoded.
// ============================================================

(function () {
  'use strict';

  const DATA_URL = 'https://raw.githubusercontent.com/jackstraw923/SureBetArcher/main/Docs/data/summary.json';

  // ── NAV HTML ────────────────────────────────────────────────
  // Canonical nav. Terminology-compliant. Edit once here.
  const NAV_HTML = `
<nav class="nav" id="site-nav">
  <a href="/index.html" class="nav-logo">
    <span class="t-wordmark">Arc<em>Vest</em></span>
  </a>
  <div class="nav-links" id="nav-links">
    <a href="/index.html">HOME</a>
    <a href="/daily-card.html">DAILY CARD</a>
    <a href="/odds.html">ODDS</a>
    <a href="/scorecard.html">SCORECARD</a>
    <a href="/performance-log.html">PERFORMANCE LOG</a>
    <a href="/vault.html">EDGEVAULT</a>
    <a href="/membership.html">MEMBERSHIP</a>
  </div>
  <a href="/sign-in.html" class="nav-cta">SIGN IN</a>
  <button class="nav-hamburger" id="nav-hamburger"
          aria-label="Open navigation menu" aria-expanded="false">
    <span></span><span></span><span></span>
  </button>
</nav>
<div class="nav-mobile" id="nav-mobile" role="navigation" aria-label="Mobile navigation">
  <a href="/index.html">HOME</a>
  <a href="/daily-card.html">DAILY CARD</a>
  <a href="/odds.html">ODDS</a>
  <a href="/scorecard.html">SCORECARD</a>
  <a href="/performance-log.html">PERFORMANCE LOG</a>
  <a href="/vault.html">EDGEVAULT</a>
  <a href="/membership.html">MEMBERSHIP</a>
  <a href="/sign-in.html">SIGN IN</a>
</div>`;

  // ── FOOTER HTML — STANDARD ───────────────────────────────────
  // Main content pages: includes Reset 4 baseline + last-run span.
  // Terminology-compliant. Disclosure updated to "Not investment advice."
  const FOOTER_STANDARD_HTML = `
<footer class="footer">
  <div class="footer-inner">
    <div class="footer-brand">
      <a href="/index.html" class="t-wordmark" style="text-decoration:none;">Arc<em>Vest</em></a>
      <p class="footer-disclaimer">
        ArcVest is a quantitative advisory framework for evaluating sports-market prices and
        portfolio risk. For informational purposes only. Not investment advice. Past model
        performance does not guarantee future results. Must be 21 or older. Only available
        where permitted by applicable law. ArcVest uses non-intrusive advertising to keep
        the platform accessible. Pro subscribers are ad-free.
      </p>
      <span class="footer-copy">
        Reset 4 baseline: April 23, 2026 &nbsp;·&nbsp; Last run: <span id="footer-last-run">—</span>
      </span>
    </div>
    <div class="footer-links">
      <a href="/about.html">ABOUT</a>
      <a href="/privacy.html">PRIVACY POLICY</a>
      <a href="/terms.html">TERMS OF USE</a>
      <span class="footer-copy" style="margin-top:var(--space-3);">© 2026 Mountain Capital, LLC</span>
    </div>
  </div>
</footer>`;

  // ── FOOTER HTML — MINIMAL ────────────────────────────────────
  // Legal pages, sign-in, thank-you: copyright + links only.
  const FOOTER_MINIMAL_HTML = `
<footer style="border-top:1px solid var(--border);padding:var(--space-4) var(--page-padding-x);text-align:center;">
  <p class="t-disclaimer">
    © 2026 Mountain Capital, LLC &nbsp;·&nbsp;
    <a href="/privacy.html" style="color:var(--dim);">Privacy</a> &nbsp;·&nbsp;
    <a href="/terms.html" style="color:var(--dim);">Terms</a> &nbsp;·&nbsp;
    <a href="/about.html" style="color:var(--dim);">About</a>
    &nbsp;·&nbsp; For informational purposes only. Not investment advice.
  </p>
</footer>`;

  // ── INJECT NAV ───────────────────────────────────────────────
  const navRoot = document.getElementById('nav-root');
  if (navRoot) {
    navRoot.outerHTML = NAV_HTML;
  }

  // ── INJECT FOOTER ────────────────────────────────────────────
  const footerRoot = document.getElementById('footer-root');
  if (footerRoot) {
    const variant = footerRoot.getAttribute('data-variant');
    footerRoot.outerHTML = (variant === 'minimal')
      ? FOOTER_MINIMAL_HTML
      : FOOTER_STANDARD_HTML;
  }

  // ── NAV: ACTIVE STATE ────────────────────────────────────────
  // Runs after injection so links exist in DOM.
  function setNavActive() {
    const path = window.location.pathname.replace(/\/$/, '') || '/index.html';
    document.querySelectorAll('.nav-links a, .nav-mobile a').forEach(function (a) {
      const href = (a.getAttribute('href') || '').replace(/\/$/, '');
      if (path.endsWith(href) || (path === '' && href.includes('index'))) {
        a.classList.add('active');
      }
    });
  }

  // ── NAV: HAMBURGER ───────────────────────────────────────────
  function initHamburger() {
    const hamburger  = document.getElementById('nav-hamburger');
    const mobileMenu = document.getElementById('nav-mobile');
    if (!hamburger || !mobileMenu) return;
    hamburger.addEventListener('click', function () {
      const isOpen = mobileMenu.classList.toggle('open');
      hamburger.setAttribute('aria-expanded', isOpen);
    });
  }

  // ── NAV: TOURNAMENTS CONDITIONAL LINK ───────────────────────
  // Injected after ODDS when summary.json returns tournaments_active=true.
  function injectTournamentsLink(active) {
    if (!active) return;
    const link = '<a href="/tournaments.html">TOURNAMENTS</a>';
    const oddsD = document.querySelector('.nav-links a[href*="odds"]');
    if (oddsD) oddsD.insertAdjacentHTML('afterend', link);
    const oddsM = document.querySelector('.nav-mobile a[href*="odds"]');
    if (oddsM) oddsM.insertAdjacentHTML('afterend', link);
    // Re-run active state after injection in case this is tournaments.html
    setNavActive();
  }

  // ── FOOTER: LAST RUN ─────────────────────────────────────────
  // Populates footer-last-run span on standard footer pages.
  function setFooterLastRun(lastRun) {
    const el = document.getElementById('footer-last-run');
    if (!el || !lastRun) return;
    try {
      const d = new Date(lastRun);
      const formatted = d.toLocaleDateString('en-US', {
        month: 'short', day: 'numeric', hour: 'numeric',
        minute: '2-digit', hour12: true
      });
      el.textContent = formatted;
    } catch (e) {
      el.textContent = lastRun;
    }
  }

  // ── SUMMARY.JSON FETCH ───────────────────────────────────────
  // Single fetch serves both tournaments injection and footer last-run.
  // Pages that already fetch summary.json for their own data still work —
  // this is a separate lightweight fetch and results are independent.
  fetch(DATA_URL)
    .then(function (r) { return r.json(); })
    .then(function (s) {
      injectTournamentsLink(s.tournaments_active);
      setFooterLastRun(s.last_run);
    })
    .catch(function () { /* silent fail — UI degrades gracefully */ });

  // ── INIT ─────────────────────────────────────────────────────
  setNavActive();
  initHamburger();

})();
