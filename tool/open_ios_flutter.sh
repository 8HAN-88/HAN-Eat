#!/usr/bin/env bash
# Единственный поддерживаемый способ открыть iOS-сборку Flutter-приложения HAN Eat в Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter не найден в PATH. Добавьте SDK Flutter в PATH и повторите." >&2
  exit 1
fi

flutter pub get
# Нужен для CocoaPods (Flutter.xcframework); без этого pod install падает.
flutter precache --ios

(cd ios && pod install)

echo ""
echo "Открываю ios/Runner.xcworkspace (схема Runner, не отдельный SwiftUI-проект)."
open "${ROOT}/ios/Runner.xcworkspace"

echo ""
echo "Дальше: в Xcode выберите симулятор iPhone и ▶ Run, либо в терминале:"
echo "  cd \"$ROOT\" && flutter run"
