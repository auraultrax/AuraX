importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

const firebaseConfig = { apiKey: 'AIzaSyC4thDZHipRZQSeZGyKXzeh-m20EC_-rcKg', authDomain: 'aura-ultra-x.firebaseapp.com', projectId: 'aura-ultra-x', storageBucket: 'aura-ultra-x.firebasestorage.app', messagingSenderId: '931526439447', appId: '1:931526439447:web:06aa1a89e0ad98407f6252' };
try { firebase.initializeApp(firebaseConfig); } catch (_) {}
let messaging = null;
try { messaging = firebase.messaging(); } catch (_) {}

const CACHE_NAME = 'aura-x-v4';

if (messaging) {
  messaging.onBackgroundMessage(payload => {
    const data = payload?.data || payload?.notification || {};
    const title = data.title || 'Aura Ultra X';
    const body = data.body || data.text || 'Yeni bildirim';
    self.registration.showNotification(title, {
      body,
      icon: './AuraX-icon-192.png',
      badge: './AuraX-icon-192.png',
      tag: data.tag || ('aurax-' + Date.now()),
      renotify: true,
      data: { roomId: data.roomId || null }
    });
  });
}

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const roomId = event.notification?.data?.roomId;
  const target = new URL('./', self.location.origin).href + (roomId ? `?room=${encodeURIComponent(roomId)}` : '');
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    const existing = list.find(c => 'focus' in c);
    if (existing) { existing.focus(); existing.postMessage({ type: 'AURA_NOTIFICATION_CLICK', roomId: roomId || null }); return; }
    if (clients.openWindow) return clients.openWindow(target);
  }));
});

const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './AuraX-icon-192.png',
  './AuraX-icon-512.png'
];

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
        keys
          .filter(key => key !== CACHE_NAME)
          .map(key => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Cross-origin resources (Firebase/CDN/etc.) are handled by the browser.
  // Only cache the same-origin Aura X application.
  if (url.origin !== self.location.origin) return;

  // HTML navigations: network first, old app as offline fallback.
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

  // Static files: cache first, then update from network.
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
