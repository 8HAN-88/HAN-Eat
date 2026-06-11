#!/usr/bin/env bash
# Запускает команду Flutter с --dart-define из .env (и env HANEAT_API_BASE / APP_ENV).
# Пример: APP_ENV=staging HANEAT_API_BASE=https://staging.example ./scripts/with_dart_defines.sh flutter build appbundle --release
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEFINES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DEFINES+=("$line")
done < <(./scripts/load_dart_defines.sh)

exec "$@" "${DEFINES[@]}"
