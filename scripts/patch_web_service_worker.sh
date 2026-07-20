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

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (e) {}
      try {
        await self.registration.unregister();
      } catch (e) {
        console.warn('HAN Eat: service worker unregister failed', e);
      }
    })()
  );
});

// Never intercept fetches — stale cached shells cause Safari boot failures.
self.addEventListener('fetch', () => {});
EOF

echo "✓ patched flutter_service_worker.js (no client reload loop)"
