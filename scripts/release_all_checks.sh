#!/usr/bin/env bash
# Полный локальный прогон перед релизом (клиент + опционально backend + prod smoke).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROD_API="${PROD_API:-https://api.haneat.app}"
RUN_PROD_SMOKE="${RUN_PROD_SMOKE:-0}"

echo "========== 1/4 Client stability =========="
./scripts/check_client_stability.sh

echo ""
echo "========== 2/4 Pre-release (Flutter + backend unit) =========="
SKIP_STABILITY=1 ./scripts/pre_release_check.sh

echo ""
echo "========== 3/4 Pre-TestFlight checklist =========="
if ./scripts/pre_testflight_check.sh; then
  echo "  pre_testflight: OK (warnings допустимы)"
else
  echo "  pre_testflight: есть FAIL — исправьте перед загрузкой в App Store Connect"
  exit 1
fi

if [[ "$RUN_PROD_SMOKE" == "1" ]]; then
  echo ""
  echo "========== 4/4 Production API smoke =========="
  ./scripts/verify_production_api.sh "$PROD_API"
else
  echo ""
  echo "========== 4/4 Production smoke (пропуск) =========="
  echo "  Запустите: RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh"
fi

echo ""
echo "========== Готово к сборке =========="
echo "  iOS:     ./scripts/build_ios_release.sh $PROD_API"
echo "  Android: ./scripts/build_android_release.sh $PROD_API"
echo "  Устройство: ./scripts/run_ios_physical.sh"
echo "  Чеклист: docs/STABILITY.md"
