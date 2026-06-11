#!/usr/bin/env bash
# Печатает строки --dart-define=... для flutter run/build (по одной на строку).
# Читает корневой .env; переопределение: HANEAT_API_BASE=... ./scripts/load_dart_defines.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

_read_env() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  local line
  line="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  local val="${line#*=}"
  val="${val%$'\r'}"
  val="${val#\"}"
  val="${val%\"}"
  val="${val#\'}"
  val="${val%\'}"
  printf '%s' "$val"
}

API_BASE="${HANEAT_API_BASE:-$(_read_env HANEAT_API_BASE)}"
API_BASE="${API_BASE:-https://api.haneat.app}"
APP_ENV_VAL="${APP_ENV:-production}"
WEB_ID="${GOOGLE_WEB_CLIENT_ID:-$(_read_env GOOGLE_WEB_CLIENT_ID)}"
IOS_ID="${GOOGLE_IOS_CLIENT_ID:-$(_read_env GOOGLE_IOS_CLIENT_ID)}"

printf '%s\n' "--dart-define=HANEAT_API_BASE=${API_BASE}"
printf '%s\n' "--dart-define=APP_ENV=${APP_ENV_VAL}"
if [[ -n "$WEB_ID" ]]; then
  printf '%s\n' "--dart-define=GOOGLE_WEB_CLIENT_ID=${WEB_ID}"
fi
if [[ -n "$IOS_ID" ]]; then
  printf '%s\n' "--dart-define=GOOGLE_IOS_CLIENT_ID=${IOS_ID}"
fi
