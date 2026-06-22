#!/usr/bin/env bash
# Flutter offline-first SW перезагружает вкладки на activate → бесконечный reload.
# Заменяем на безопасный: только снимаем регистрацию, без client.navigate().
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
        await self.registration.unregister();
      } catch (e) {
        console.warn('HAN Eat: service worker unregister failed', e);
      }
    })()
  );
});
EOF

echo "✓ patched flutter_service_worker.js (no client reload loop)"
