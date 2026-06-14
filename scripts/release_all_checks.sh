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

echo ""
echo "========== 4/5 Pre-web release =========="
if ./scripts/pre_web_release_check.sh; then
  echo "  pre_web_release: OK"
else
  echo "  pre_web_release: есть FAIL — исправьте перед деплоем haneat.app"
  exit 1
fi

if [[ "$RUN_PROD_SMOKE" == "1" ]]; then
  echo ""
  echo "========== 5/6 Production API smoke =========="
  ./scripts/verify_production_api.sh "$PROD_API"
  echo ""
  echo "========== 6/6 Web production smoke =========="
  ./scripts/verify_web_prod.sh
else
  echo ""
  echo "========== 5/6 Production smoke (пропуск) =========="
  echo "  Запустите: RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh"
fi

echo ""
echo "========== Готово к сборке =========="
echo "  Web:     ./scripts/build_web_release.sh $PROD_API"
echo "  Web deploy: bash scripts/deploy_web_timeweb.sh"
echo "  Web smoke: ./scripts/verify_web_prod.sh"
echo "  TWA Play: ./scripts/build_twa_release.sh build"
echo "  Android: ./scripts/build_android_release.sh $PROD_API"
echo "  iOS:     ./scripts/build_ios_release.sh $PROD_API"
echo "  Устройство: ./scripts/run_ios_physical.sh"
echo "  Чеклист: docs/RELEASE_WEB_AND_PLAY.md"
