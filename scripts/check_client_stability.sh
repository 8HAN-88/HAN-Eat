#!/usr/bin/env bash
# Локальные проверки стабильности клиента (сервисы, шрифты, define-скрипты).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
ok() { echo "  OK $1"; }
fail_msg() { echo "  FAIL $1"; fail=1; }

echo "== Client stability check =="

echo ""
echo "-- Assets --"
if [[ -f assets/fonts/Manrope-VariableFont.ttf ]]; then
  ok "Manrope bundled"
else
  fail_msg "Нет assets/fonts/Manrope-VariableFont.ttf"
fi

echo ""
echo "-- dart-define script --"
if out="$(./scripts/load_dart_defines.sh 2>/dev/null)" && [[ "$out" == *HANEAT_API_BASE=* ]]; then
  ok "load_dart_defines.sh"
else
  fail_msg "load_dart_defines.sh"
fi

echo ""
echo "-- Flutter tests (local services) --"
if flutter test \
  test/favorites_service_test.dart \
  test/shopping_service_test.dart \
  test/feed_load_helper_test.dart; then
  ok "unit tests"
else
  fail_msg "unit tests"
fi

echo ""
echo "-- flutter_contacts (iOS 26 UIScene) --"
FC_VER="$(grep 'flutter_contacts:' pubspec.yaml | head -1)"
if [[ "$FC_VER" =~ flutter_contacts:\ \^?2\. ]]; then
  ok "flutter_contacts v2+ ($FC_VER)"
else
  fail_msg "flutter_contacts < 2.0 крашит на iOS 26 (UIScene): $FC_VER"
fi

echo ""
echo "-- Crash-prone patterns --"
if rg -n "static final FirebaseFirestore _firestore = FirebaseFirestore\\.instance" lib/ 2>/dev/null; then
  fail_msg "Найден static FirebaseFirestore до init — используйте LazyFirebase"
else
  ok "нет static FirebaseFirestore.instance"
fi

echo ""
echo "-- Flutter analyze (bootstrap / gates) --"
if flutter analyze \
  lib/main.dart \
  lib/app/bootstrap.dart \
  lib/app/startup_shell.dart \
  lib/core/storage/hive_bootstrap.dart \
  lib/core/app_stability_guard.dart \
  lib/widgets/services_ready_gate.dart \
  lib/services/shopping_service.dart \
  lib/services/favorites_service.dart \
  lib/services/meal_plan_service.dart \
  lib/core/theme/app_typography.dart; then
  ok "analyze"
else
  fail_msg "analyze"
fi

echo ""
if [[ $fail -ne 0 ]]; then
  echo "== FAILED =="
  exit 1
fi
echo "== Client stability OK =="
echo "Дальше: ./scripts/run_ios_physical.sh и чеклист docs/STABILITY.md"
