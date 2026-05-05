// ============================================================
// ArcVest Service Worker
// Step 12 of SITE-PASS-1 | Mountain Engineering
// Version 1.0 | April 2026
//
// STRATEGY:
// - App shell (HTML, CSS, JS, fonts): Cache-first, network fallback
// - JSON data files: Network-first, cache fallback (stale-while-revalidate)
// - Everything else: Network-first
//
// This ensures:
// - Pages load instantly on repeat visits (shell from cache)
// - Data is always fresh when network is available
// - Offline / poor connection gracefully falls back to last cached data
// ============================================================

const CACHE_VERSION   = 'arcvest-v1';
const DATA_CACHE      = 'arcvest-data-v1';
const DATA_BASE_URL   = 'https://raw.githubusercontent.com/jackstraw923/SureBetArcher/main/Docs/data/';

// ── App shell files — cached on install ──
const SHELL_FILES = [
  '/index.html',
  '/daily-card.html',
  '/odds.html',
  '/scorecard.html',
  '/performance-log.html',
  '/vault.html',
  '/tournaments.html',
  '/membership.html',
  '/about.html',
  '/privacy.html',
  '/terms.html',
  '/sign-in.html',
  '/thank-you.html',
  '/arcvest.css',
  // Google Fonts — cached for offline use
  'https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@300;400;500&family=DM+Sans:wght@300;400;500&family=Syne:wght@800&display=swap',
];

// ── Data files — network-first with cache fallback ──
// These update daily; always prefer fresh network response
const DATA_FILES = [
  'summary.json',
  'daily_picks.json',
  'scorecard.json',
  'paper_log.json',
  'market.json',
  'performance_log.json',
  'pick_manifest.json',
  'bracket_nba.json',
  'bracket_nhl.json',
  'bracket_atp.json',
  'bracket_wta.json',
];

// ── Install: pre-cache app shell ──
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then(cache => {
        // Cache shell files — individual failures don't abort install
        return Promise.allSettled(
          SHELL_FILES.map(url =>
            cache.add(url).catch(err => {
              console.warn('[SW] Failed to cache:', url, err);
            })
          )
        );
      })
      .then(() => self.skipWaiting())
  );
});

// ── Activate: clean up old caches ──
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key !== CACHE_VERSION && key !== DATA_CACHE)
          .map(key => {
            console.log('[SW] Deleting old cache:', key);
            return caches.delete(key);
          })
      )
    ).then(() => self.clients.claim())
  );
});

// ── Fetch: route requests ──
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Only handle GET requests
  if (event.request.method !== 'GET') return;

  // ── JSON data files: network-first, cache fallback ──
  if (url.href.startsWith(DATA_BASE_URL)) {
    event.respondWith(networkFirstData(event.request));
    return;
  }

  // ── Third-party scripts (Lucide, Chart.js, etc.): stale-while-revalidate ──
  if (
    url.hostname === 'unpkg.com' ||
    url.hostname === 'cdn.jsdelivr.net' ||
    url.hostname === 'fonts.googleapis.com' ||
    url.hostname === 'fonts.gstatic.com'
  ) {
    event.respondWith(staleWhileRevalidate(event.request));
    return;
  }

  // ── App shell (same origin): cache-first, network fallback ──
  if (url.origin === self.location.origin) {
    event.respondWith(cacheFirstShell(event.request));
    return;
  }

  // ── Everything else: network-only ──
  // (affiliate links, external analytics, etc. should not be cached)
});

// ── Strategy: Network-first for data, cache as fallback ──
async function networkFirstData(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(DATA_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await caches.match(request);
    if (cached) return cached;
    // Return a minimal offline JSON response
    return new Response(
      JSON.stringify({ offline: true, message: 'No cached data available' }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  }
}

// ── Strategy: Cache-first for app shell ──
async function cacheFirstShell(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_VERSION);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    // Return offline fallback page if available
    const fallback = await caches.match('/index.html');
    return fallback || new Response('Offline', { status: 503 });
  }
}

// ── Strategy: Stale-while-revalidate for third-party assets ──
async function staleWhileRevalidate(request) {
  const cache  = await caches.open(CACHE_VERSION);
  const cached = await cache.match(request);
  // Kick off network fetch in background regardless
  const fetchPromise = fetch(request).then(response => {
    if (response.ok) cache.put(request, response.clone());
    return response;
  }).catch(() => cached);
  // Return cached immediately if available, otherwise wait for network
  return cached || fetchPromise;
}

// ── Push notifications (Phase 2) ──
// Receives push events when the morning COMMIT run completes.
// Notification payload from server should include:
//   { title, body, url, icon, badge }
self.addEventListener('push', event => {
  if (!event.data) return;

  let payload;
  try {
    payload = event.data.json();
  } catch {
    payload = { title: 'ArcVest', body: event.data.text() };
  }

  const options = {
    body:    payload.body    || "Today's Daily Card is ready.",
    icon:    payload.icon    || '/icons/icon-192.png',
    badge:   payload.badge   || '/icons/icon-192.png',
    tag:     'arcvest-commit',   // replaces prior notification if still showing
    renotify: true,
    data: {
      url: payload.url || '/daily-card.html',
    },
    actions: [
      { action: 'view-card',     title: 'View Daily Card' },
      { action: 'view-scorecard', title: 'View Scorecard'  },
    ],
  };

  event.waitUntil(
    self.registration.showNotification(
      payload.title || 'ArcVest — Morning Run Complete',
      options
    )
  );
});

// ── Notification click ──
self.addEventListener('notificationclick', event => {
  event.notification.close();

  let targetUrl = '/daily-card.html';

  if (event.action === 'view-scorecard') {
    targetUrl = '/scorecard.html';
  } else if (event.notification.data?.url) {
    targetUrl = event.notification.data.url;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(windowClients => {
        // If a window is already open, focus it and navigate
        for (const client of windowClients) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            client.navigate(targetUrl);
            return client.focus();
          }
        }
        // Otherwise open a new window
        if (clients.openWindow) {
          return clients.openWindow(targetUrl);
        }
      })
  );
});

// ── Background sync (Phase 2 — confirmed picks sync) ──
// When the subscriber's confirmed_picks action fails due to no connectivity,
// background sync retries when connection is restored.
self.addEventListener('sync', event => {
  if (event.tag === 'sync-confirmed-picks') {
    event.waitUntil(syncConfirmedPicks());
  }
});

async function syncConfirmedPicks() {
  // TODO Phase 2: Retrieve queued confirmed pick updates from IndexedDB
  // and POST to the subscriber sync endpoint when back online.
  console.log('[SW] Background sync: confirmed picks — Phase 2 implementation pending');
}
