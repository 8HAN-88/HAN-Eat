#!/usr/bin/env bash
# Release-сборка Flutter Web с production API.
# Использование: ./scripts/build_web_release.sh [API_BASE] [APP_VARIANT]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${1:-https://api.haneat.app}"
APP_VARIANT="${2:-${APP_VARIANT:-social}}"

cd "$ROOT"
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
echo "== HAN Eat: flutter build web (API=$API_BASE, variant=$APP_VARIANT, build=$BUILD_ID) =="

if [[ -f "$ROOT/assets/app_icon_source.png" ]]; then
  echo "-- PWA icons (black bg) --"
  python3 "$ROOT/scripts/generate_web_pwa_icons.py"
fi

# dart2js + canvaskit only. Dual wasm builds break Safari/iOS (skwasm/WasmGC)
# and trigger white screens + browser "server stopped responding" during boot.
HANEAT_API_BASE="$API_BASE" ./scripts/with_dart_defines.sh \
  flutter build web \
  --release \
  --base-href / \
  --pwa-strategy none \
  --no-web-resources-cdn \
  --no-wasm-dry-run \
  --dart-define=APP_VARIANT="$APP_VARIANT" \
  --dart-define=WEB_BUILD_ID="$BUILD_ID"

bash "$ROOT/scripts/patch_web_cache_bust.sh" "$BUILD_ID"
bash "$ROOT/scripts/patch_web_service_worker.sh"

echo ""
echo "✓ Web build: build/web/"
echo "  Локальный просмотр: cd build/web && python3 -m http.server 8080"
echo "  Деплой: bash scripts/deploy_web_timeweb.sh"
