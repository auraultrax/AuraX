const CACHE_NAME = 'aura-x-v5';

const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './AuraX-icon-192.png',
  './AuraX-icon-512.png'
];

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const roomId = event.notification?.data?.roomId;
  const target = new URL('./', self.location.origin).href + (roomId ? `?room=${encodeURIComponent(roomId)}` : '');
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    const existing = list.find(c => 'focus' in c);
    if (existing) {
      existing.focus();
      existing.postMessage({ type: 'AURA_NOTIFICATION_CLICK', roomId: roomId || null });
      return;
    }
    if (clients.openWindow) return clients.openWindow(target);
  }));
});

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then(response => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put('./index.html', copy));
          return response;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(cached => {
      const network = fetch(event.request, { cache: 'no-store' })
        .then(response => {
          if (response && response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
