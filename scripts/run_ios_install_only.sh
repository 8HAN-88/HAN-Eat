#!/usr/bin/env bash
# Установка на iPhone без ожидания отладчика.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ID="${1:-00008110-000E5CC611F9801E}"

echo "Устройство: $DEVICE_ID"
echo ""
echo "⚠️  После установки ОБЯЗАТЕЛЬНО на iPhone:"
echo "   Настройки → Основные → VPN и управление устройством → Доверять разработчику"
echo "   Настройки → Конфиденциальность → Режим разработчика → ВКЛ"
echo ""

./scripts/ios_ensure_pods.sh

echo "Сборка release (стабильнее на iOS 26, без ожидания отладчика)…"
APP_ENV=development ./scripts/with_dart_defines.sh flutter build ios --release

echo "Установка…"
flutter install -d "$DEVICE_ID"

echo ""
echo "✓ Установлено. Откройте HAN Eat на iPhone вручную."
echo "  Белый экран + вылет без доверия профиля — нормальное поведение iOS."
