#!/usr/bin/env bash
# Staging AAB для Internal testing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${1:-https://staging-api.haneat.app}"

cd "$ROOT"
HANEAT_API_BASE="$API_BASE" APP_ENV=staging ./scripts/with_dart_defines.sh flutter build appbundle --release

echo "✓ Staging AAB (API=$API_BASE, APP_ENV=staging)"
