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

# App lives under /app/ so stuck Safari/YaBrowser caches of old "/" shells cannot
# keep serving a broken index that never loads Flutter.
# dart2js + canvaskit only (no wasm dual-build).
#
# Mid-build watcher keeps web_plugin_registrant slim (video/WebView/Firebase out
# of the first JS download). A post-pass recompiles dart2js to make that reliable.
export HANEAT_API_BASE="$API_BASE"
export APP_VARIANT="$APP_VARIANT"
export WEB_BUILD_ID="$BUILD_ID"
python3 "$ROOT/scripts/patch_web_plugin_registrant_during_build.py" -- \
  ./scripts/with_dart_defines.sh \
  flutter build web \
  --release \
  --base-href /app/ \
  --pwa-strategy none \
  --no-web-resources-cdn \
  --no-wasm-dry-run \
  --dart-define=APP_VARIANT="$APP_VARIANT" \
  --dart-define=WEB_BUILD_ID="$BUILD_ID"

echo "-- recompile with slim web plugins (cold-start chunk) --"
python3 "$ROOT/scripts/recompile_web_slim_plugins.py"

bash "$ROOT/scripts/patch_web_cache_bust.sh" "$BUILD_ID"
bash "$ROOT/scripts/patch_web_service_worker.sh"
bash "$ROOT/scripts/prepare_web_root.sh" "$BUILD_ID"

echo ""
echo "✓ Web build: build/web_root/ (app at /app/)"
echo "  Локальный просмотр: cd build/web_root && python3 -m http.server 8080"
echo "  Деплой: bash scripts/deploy_web_timeweb.sh"
