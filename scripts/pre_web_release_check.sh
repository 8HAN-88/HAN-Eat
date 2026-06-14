#!/usr/bin/env bash
# Чеклист перед деплоем Flutter Web на haneat.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
warn=0

check() { echo "  OK $1"; }
warn_msg() { echo "  WARN $1"; warn=1; }
fail_msg() { echo "  FAIL $1"; fail=1; }

echo "== Pre-web release check =="

echo ""
echo "-- Version --"
if grep -qE '^version:' pubspec.yaml; then
  check "version: $(grep '^version:' pubspec.yaml)"
else
  fail_msg "Нет version в pubspec.yaml"
fi

echo ""
echo "-- Web meta --"
if grep -qi 'HAN Eat' web/index.html 2>/dev/null; then
  check "web/index.html title/branding"
else
  warn_msg "Обновите title/description в web/index.html"
fi
if grep -qi 'HAN Eat' web/manifest.json 2>/dev/null; then
  check "web/manifest.json"
else
  warn_msg "Обновите name/description в web/manifest.json"
fi

echo ""
echo "-- API / OAuth --"
if [[ -f .env ]] && grep -q 'GOOGLE_WEB_CLIENT_ID=' .env; then
  check "GOOGLE_WEB_CLIENT_ID в .env"
else
  warn_msg "Добавьте GOOGLE_WEB_CLIENT_ID в .env (Google Sign-In на web)"
fi
if python3 scripts/verify_google_signin.py 2>/dev/null; then
  :
else
  warn_msg "verify_google_signin.py — см. docs/GOOGLE_SIGNIN_SETUP.md"
fi

echo ""
echo "-- Legal --"
for url in "https://api.haneat.app/privacy" "https://api.haneat.app/terms"; do
  if curl -sf -o /dev/null -w '' --max-time 10 "$url"; then
    check "$url"
  else
    warn_msg "Недоступен $url — нужен для Play и веба"
  fi
done

echo ""
echo "-- Flutter analyze (web entrypoints) --"
if dart analyze lib/main.dart lib/app/ lib/core/network/ 2>/dev/null; then
  check "dart analyze"
else
  fail_msg "dart analyze — исправьте ошибки"
fi

echo ""
echo "-- Trial build --"
if HANEAT_API_BASE="${HANEAT_API_BASE:-https://api.haneat.app}" \
  ./scripts/with_dart_defines.sh flutter build web --release --base-href / 2>&1 | tail -3; then
  check "flutter build web"
else
  fail_msg "flutter build web не собрался"
fi

echo ""
if [[ "$fail" -gt 0 ]]; then
  echo "Итог: FAIL ($fail ошибок, $warn предупреждений)"
  exit 1
fi
echo "Итог: OK ($warn предупреждений — проверьте WARN)"
echo ""
echo "Деплой: ./scripts/build_web_release.sh && bash scripts/deploy_web_timeweb.sh"
