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
echo "-- smoke_launch --"
"$ROOT/scripts/smoke_launch.sh" "$BASE"
