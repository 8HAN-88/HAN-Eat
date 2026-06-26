#!/usr/bin/env bash
# Smoke stability features on production (realtime, auth guards, web version).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-https://api.haneat.app}"
WEB_ORIGIN="${WEB_ORIGIN:-https://haneat.app}"
fail=0

ok() { echo "  OK $1"; }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

echo "== Stability production smoke =="
echo "API: $API_BASE"
echo "Web: $WEB_ORIGIN"

echo ""
echo "-- API health --"
if curl -sf --max-time 15 "$API_BASE/health" >/dev/null; then
  ok "health"
else
  bad "health"
fi

echo ""
echo "-- Realtime SSE (auth required) --"
rt_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  "$API_BASE/api/v1/realtime/stream")"
if [[ "$rt_code" == "401" || "$rt_code" == "403" ]]; then
  ok "realtime/stream requires auth ($rt_code)"
else
  bad "realtime/stream expected 401/403, got $rt_code"
fi

echo ""
echo "-- Privacy guards (no auth) --"
for path in \
  "/api/v1/notifications/unread-count" \
  "/api/v1/users/1/saved"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    "$API_BASE$path")"
  if [[ "$code" == "401" || "$code" == "403" ]]; then
    ok "$path → $code"
  else
    bad "$path expected 401/403, got $code"
  fi
done

echo ""
echo "-- Web deploy marker --"
if curl -sf --max-time 15 "$WEB_ORIGIN/version.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
bn=d.get('build_number','')
assert bn, 'missing build_number'
print('build_number', bn)
" 2>/dev/null; then
  ok "version.json"
else
  bad "version.json"
fi

echo ""
echo "-- Authenticated API smoke --"
if BASE_URL="$API_BASE" python3 "$ROOT/backend/scripts/smoke_launch.py"; then
  ok "smoke_launch"
else
  bad "smoke_launch"
fi

echo ""
if [[ "$fail" -gt 0 ]]; then
  echo "Итог: FAIL ($fail)"
  exit 1
fi
echo "Итог: OK — stability smoke passed"
echo ""
echo "Ручной чеклист (клиент):"
echo "  1. SSE realtime/stream в DevTools (pending 200)"
echo "  2. Лента / чаты / профиль открываются из кэша"
echo "  3. Уведомления: бейдж + список"
echo "  4. Рилсы: первый сразу, свайп вперёд/назад без паузы"
echo "  5. Меню: рекомендации + повторный поиск из кэша"
echo "  6. Глобальный поиск: повторный запрос из кэша"
