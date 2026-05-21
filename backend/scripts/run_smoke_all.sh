#!/usr/bin/env bash
# Публичные + опционально auth AI scan smoke.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${BASE_URL:-http://127.0.0.1:5001}"

echo "=== Public API ==="
"$ROOT/scripts/smoke_public_api.sh" "$BASE"

if [[ -n "${SMOKE_PASSWORD:-}" ]]; then
  export SMOKE_EMAIL="${SMOKE_EMAIL:-smoke$(date +%s)@example.com}"
  export SMOKE_AUTO_REGISTER="${SMOKE_AUTO_REGISTER:-1}"
  export SMOKE_PASSWORD="${SMOKE_PASSWORD:-password123}"
  echo ""
  echo "=== Subscriptions (auth) $SMOKE_EMAIL ==="
  python3.11 "$ROOT/scripts/smoke_subscriptions.py" || python3 "$ROOT/scripts/smoke_subscriptions.py"
  echo ""
  if [[ -n "${ADMIN_EMAIL:-}" && -n "${ADMIN_PASSWORD:-}" ]]; then
    echo "=== Admin refunds $ADMIN_EMAIL ==="
    python3.11 "$ROOT/scripts/smoke_admin_refunds.py" || python3 "$ROOT/scripts/smoke_admin_refunds.py"
    echo ""
  fi
  echo "=== AI Scan (auth) $SMOKE_EMAIL ==="
  python3.11 "$ROOT/scripts/smoke_ai_scan_auth.py" || python3 "$ROOT/scripts/smoke_ai_scan_auth.py"
else
  echo ""
  echo "SKIP auth smoke (set SMOKE_PASSWORD, optional SMOKE_EMAIL, SMOKE_AUTO_REGISTER=1)"
fi

echo ""
echo "All smoke checks finished."
