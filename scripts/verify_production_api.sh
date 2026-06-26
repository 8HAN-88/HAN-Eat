#!/usr/bin/env bash
# Быстрая проверка production API (readiness + smoke).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-https://api.haneat.app}"

echo "== Production API: $BASE =="

echo ""
echo "-- health --"
if curl -sf --max-time 15 "$BASE/health" >/dev/null; then
  echo "  OK health"
else
  echo "  FAIL health"
  exit 1
fi

echo ""
echo "-- readiness --"
ready=$(curl -sf --max-time 20 "$BASE/api/v1/system/readiness" 2>/dev/null || echo '{}')
echo "$ready" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  ready:', d.get('ready'))
for i in (d.get('issues') or []):
    print('  issue:', i)
" 2>/dev/null || echo "  (parse skip)"

echo ""
echo "-- realtime SSE --"
rt_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  "$BASE/api/v1/realtime/stream")"
if [[ "$rt_code" == "401" || "$rt_code" == "403" ]]; then
  echo "  OK realtime/stream requires auth ($rt_code)"
else
  echo "  FAIL realtime/stream expected 401/403, got $rt_code"
  exit 1
fi

echo ""
echo "-- smoke_launch --"
"$ROOT/scripts/smoke_launch.sh" "$BASE"
