#!/usr/bin/env bash
# Локальные проверки перед релизом (тесты + опционально smoke API).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://127.0.0.1:5001}"
RUN_SMOKE="${RUN_SMOKE:-0}"

echo "== Backend unit tests =="
cd "$ROOT/backend"
python3 -m pytest tests/test_post_poll_service.py -q

echo ""
echo "== Flutter unit tests =="
cd "$ROOT"
flutter test \
  test/url_validator_test.dart \
  test/api_error_parser_test.dart \
  test/feed_load_helper_test.dart \
  test/shopping_service_test.dart \
  test/favorites_service_test.dart

echo ""
echo "== Flutter analyze (feed/posts/chats) =="
flutter analyze \
  lib/features/feed/presentation/new_post_card.dart \
  lib/features/posts/presentation/edit_profile_post_screen.dart \
  lib/features/chat/presentation/chats_hub_screen.dart \
  lib/widgets/post_poll_section.dart \
  lib/widgets/share_action_sheet.dart \
  lib/screens/post_by_id_screen.dart

if [[ "$RUN_SMOKE" == "1" ]]; then
  echo ""
  echo "== API smoke ($API_BASE) =="
  cd "$ROOT/backend"
  python3 scripts/smoke_api_check.py --base "$API_BASE" \
    --login "${SMOKE_EMAIL:-han.test.creator@haneat.dev}"
fi

echo ""
echo "== Client stability (optional) =="
if [[ "${SKIP_STABILITY:-0}" != "1" ]]; then
  ./scripts/check_client_stability.sh
fi

echo ""
echo "Pre-release checks passed."
