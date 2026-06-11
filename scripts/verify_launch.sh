#!/usr/bin/env bash
# Проверка готовности к релизу: health + smoke + подсказки.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-http://127.0.0.1:5001}"

echo "== HAN Eat launch verify =="
echo "API: $BASE"
echo ""

fail=0

echo "== 1/3 health =="
if curl -sf "$BASE/health" >/dev/null; then
  echo "  OK health"
else
  echo "  FAIL: backend недоступен на $BASE"
  echo "  Запуск: cd backend && uvicorn app.main:app --host 127.0.0.1 --port 5001"
  exit 1
fi

echo ""
echo "== 2/3 system/readiness =="
ready_json=$(curl -sf "$BASE/api/v1/system/readiness" 2>/dev/null || echo "{}")
echo "$ready_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
issues=d.get('issues') or []
print('  ready:', d.get('ready'))
if issues:
    print('  issues:')
    for i in issues:
        print('   -', i)
" 2>/dev/null || echo "  (readiness parse skip)"

echo ""
echo "== 3/3 smoke_launch =="
export BASE_URL="$BASE"
if python3 "$ROOT/backend/scripts/smoke_launch.py"; then
  echo ""
  echo "== VERIFY OK =="
else
  fail=1
  echo ""
  echo "== VERIFY FAILED =="
fi

echo ""
echo "Ручные шаги: docs/LAUNCH_CHECKLIST.md, docs/TESTFLIGHT.md"
exit $fail
