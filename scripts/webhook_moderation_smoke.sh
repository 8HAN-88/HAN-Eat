#!/usr/bin/env bash
# Focused regression smoke for webhook moderation control-plane.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1/3 Webhook API smoke tests =="
PYTHONPATH=backend pytest backend/tests/test_webhook_api_smoke.py

echo ""
echo "== 2/3 Webhook queue service smoke tests =="
PYTHONPATH=backend pytest backend/tests/test_bot_webhook_queue_service.py

echo ""
echo "== 3/3 Flutter analyze (webhook moderation UX) =="
dart analyze \
  lib/features/moderation/presentation/moderation_dashboard_screen.dart \
  lib/features/bots/presentation/bot_detail_screen.dart \
  lib/services/moderation_service.dart

echo ""
echo "Webhook moderation smoke passed."
