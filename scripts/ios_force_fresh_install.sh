#!/usr/bin/env bash
# Полная переустановка: удаляет старую версию (убивает зависший процесс), ставит заново.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="${1:-00008110-000E5CC611F9801E}"
BUILD_MODE="${2:-release}"

echo "Устройство: ${DEVICE_ID}"
echo "Режим: ${BUILD_MODE}"
echo ""
echo "⚠️  На iPhone перед открытием:"
echo "   1. Настройки → Основные → VPN и управление устройством → Доверять разработчику"
echo "   2. Настройки → Конфиденциальность → Режим разработчика → ВКЛ"
echo "   3. Если приложение было открыто — смахните его из списка приложений"
echo ""

./scripts/ios_ensure_pods.sh
chmod +x ./scripts/ios_fix_team.sh ./scripts/ios_sync_profiles.sh
./scripts/ios_fix_team.sh
./scripts/ios_sync_profiles.sh
./scripts/ios_check_signing.sh

echo ""
echo "Сборка ${BUILD_MODE}…"
APP_ENV=development ./scripts/with_dart_defines.sh flutter build ios --"${BUILD_MODE}"

echo ""
echo "Установка (с удалением старой версии)…"
flutter install -d "${DEVICE_ID}"

echo ""
echo "✓ Чистая установка завершена. Откройте HAN Eat на iPhone."
