#!/usr/bin/env bash
# Flutter offline-first SW перезагружает вкладки на activate → бесконечный reload.
# Заменяем на безопасный kill-switch: чистим caches и снимаем регистрацию.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SW="${ROOT}/build/web/flutter_service_worker.js"

if [[ ! -f "$SW" ]]; then
  echo "patch_web_service_worker: skip (no flutter_service_worker.js)"
  exit 0
fi

cat > "$SW" <<'EOF'
'use strict';

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (e) {}
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (e) {}
      try {
        await self.clients.claim();
      } catch (e) {}
      let clients = [];
      try {
        clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      } catch (e) {}
      try {
        await self.registration.unregister();
      } catch (e) {
        console.warn('HAN Eat: service worker unregister failed', e);
      }
      // Stay on the Flutter shell. Navigating to / reopened «Открываем…».
      await Promise.all(
        clients.map((client) => {
          try {
            if (typeof client.navigate === 'function') {
              return client.navigate('/app/?go=1&sw=1');
            }
          } catch (e) {}
          return Promise.resolve();
        })
      );
    })()
  );
});

// Network-only: never serve a cached shell.
self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});
EOF

echo "✓ patched flutter_service_worker.js (no client reload loop)"
