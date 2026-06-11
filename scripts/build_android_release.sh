#!/usr/bin/env bash
# Release-сборка Android (AAB) с production API и Google OAuth из .env.
# Использование: ./scripts/build_android_release.sh [API_BASE]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${1:-}"

cd "$ROOT"
if [[ -n "$API_BASE" ]]; then
  HANEAT_API_BASE="$API_BASE" ./scripts/with_dart_defines.sh flutter build appbundle --release
else
  ./scripts/with_dart_defines.sh flutter build appbundle --release
fi

echo "✓ AAB: build/app/outputs/bundle/release"
