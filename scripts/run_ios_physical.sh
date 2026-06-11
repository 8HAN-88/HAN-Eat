#!/usr/bin/env bash
# Запуск на физическом iPhone. .env → --dart-define.
# По умолчанию: release (стабильнее debug на iOS 26 — меньше вылетов при открытии).
# Debug:        ./scripts/run_ios_physical.sh --debug
# С отладчиком:  ./scripts/run_ios_physical.sh --attach
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="00008110-000E5CC611F9801E"
ATTACH=false
REPAIR=false
BUILD_MODE="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --attach) ATTACH=true ;;
    --repair) REPAIR=true ;;
    --debug) BUILD_MODE="debug" ;;
    --profile) BUILD_MODE="profile" ;;
    --release) BUILD_MODE="release" ;;
    *) DEVICE_ID="$1" ;;
  esac
  shift
done

echo "Устройство: ${DEVICE_ID} (режим: ${BUILD_MODE})"
echo ""
echo "⚠️  ПЕРЕД ЗАПУСКОМ на iPhone:"
echo "   1. iPhone по USB (не только Wi‑Fi — установка надёжнее)"
echo "   2. Удалите старую иконку HAN Eat (если был вылет)"
echo "   3. Настройки → Основные → VPN и управление устройством"
echo "      → Доверять «Apple Development: …»"
echo "   4. Настройки → Конфиденциальность → Режим разработчика → ВКЛ"
echo "   5. iPhone разблокирован"
echo ""

if $REPAIR; then
  REPAIR_DEEP="${REPAIR_DEEP:-1}" ./scripts/ios_repair_build.sh
fi

./scripts/ios_ensure_pods.sh
chmod +x ./scripts/ios_fix_team.sh ./scripts/ios_sync_profiles.sh
./scripts/ios_fix_team.sh
./scripts/ios_sync_profiles.sh

if ! ./scripts/ios_check_signing.sh; then
  exit 1
fi

install_on_device() {
  local app_path="build/ios/iphoneos/Runner.app"
  if [[ ! -d "$app_path" ]]; then
    echo "❌ Не найден $app_path — сборка не создала .app"
    return 1
  fi
  echo "Установка на iPhone (с удалением старой версии)..."
  # flutter install снимает зависший процесс; devicectl только накладывает поверх.
  if flutter install -d "${DEVICE_ID}"; then
    return 0
  fi
  echo ""
  echo "⚠️  flutter install не сработал. Пробуем devicectl…"
  if xcrun devicectl device install app -d "${DEVICE_ID}" "$app_path" 2>&1; then
    return 0
  fi
  echo ""
  echo "❌ Установка не удалась."
  echo "   • Подключите iPhone по USB"
  echo "   • Или нажмите ▶ Run в Xcode (ios/Runner.xcworkspace)"
  return 1
}

build_with_xcode() {
  local cfg="Release"
  [[ "$BUILD_MODE" == "debug" ]] && cfg="Debug"
  echo ""
  echo "Сборка через xcodebuild (${cfg}, -allowProvisioningUpdates)..."
  cp ios/Podfile.lock ios/Pods/Manifest.lock 2>/dev/null || true
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration "$cfg" \
    -destination "id=${DEVICE_ID}" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${HAN_DEVELOPMENT_TEAM:-94NCHYWGB8}" \
    build
  local derived_app
  derived_app="$(find "${HOME}/Library/Developer/Xcode/DerivedData"/Runner-*/Build/Products/"${cfg}"-iphoneos/Runner.app -maxdepth 0 2>/dev/null | head -1)"
  if [[ -n "$derived_app" && -d "$derived_app" ]]; then
    mkdir -p build/ios/iphoneos
    rm -rf build/ios/iphoneos/Runner.app
    cp -R "$derived_app" build/ios/iphoneos/Runner.app
  fi
}

build_and_install() {
  echo ""
  echo "Сборка ${BUILD_MODE} (flutter)..."
  if APP_ENV=development ./scripts/with_dart_defines.sh flutter build ios --"${BUILD_MODE}"; then
    ./scripts/ios_restore_pods_from_cache.sh
    install_on_device
    return $?
  fi
  echo ""
  echo "⚠️  flutter build упал. Восстанавливаем Pods и пробуем xcodebuild..."
  ./scripts/ios_restore_pods_from_cache.sh
  if build_with_xcode; then
    install_on_device
    return $?
  fi
  echo ""
  echo "❌ Сборка не удалась."
  echo ""
  echo "Чаще всего Xcode не залогинен. Сделайте один раз:"
  echo "  open ios/Runner.xcworkspace"
  echo "  Xcode → Settings → Accounts → Apple ID"
  echo "  Runner → Signing → Team: Airat Hadiev (94NCHYWGB8) → ▶ Run на iPhone"
  return 1
}

if $ATTACH; then
  echo ""
  echo "Режим с отладчиком (flutter run, debug)..."
  if APP_ENV=development ./scripts/with_dart_defines.sh flutter run -d "${DEVICE_ID}" --no-dds; then
    exit 0
  fi
  echo ""
  echo "⚠️  flutter run не подключился. Пробуем сборку + установку..."
  BUILD_MODE="release"
  build_and_install
  exit $?
fi

echo ""
echo "Сборка и установка..."
if ! build_and_install; then
  echo ""
  echo "⚠️  Первая попытка упала. Быстрый ремонт..."
  ./scripts/ios_repair_build.sh
  ./scripts/ios_ensure_pods.sh
  build_and_install
fi

echo ""
echo "✓ HAN Eat установлен (${BUILD_MODE}). Откройте приложение на iPhone."
echo "  Debug:   ./scripts/run_ios_physical.sh --debug"
echo "  Отладка: ./scripts/run_ios_physical.sh --attach"
