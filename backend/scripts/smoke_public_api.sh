#!/usr/bin/env bash
# Быстрая проверка публичных эндпоинтов (без авторизации).
set -euo pipefail
BASE="${1:-http://127.0.0.1:5001}"

echo "== health =="
curl -sf "$BASE/health" | head -c 80
echo ""

echo "== ai-scan limits =="
curl -sf "$BASE/api/v1/ai-scan/limits"
echo ""

echo "== payments prices RU =="
curl -sf "$BASE/api/v1/payments/prices?country=RU" | head -c 200
echo ""

echo "== community list =="
code=$(curl -s -o /tmp/community.json -w "%{http_code}" "$BASE/api/v1/community?limit=1")
echo "HTTP $code"
head -c 120 /tmp/community.json 2>/dev/null || true
echo ""
echo "OK"
