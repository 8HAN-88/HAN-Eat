#!/usr/bin/env bash
# Быстрая чистка битого DerivedData / Pods (gRPC disk I/O, missing headers).
# Полная переустановка CDN: REPAIR_DEEP=1 ./scripts/ios_repair_build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ts() { date '+%H:%M:%S'; }

echo "[$(ts)] 1/5 Останавливаем зависшие сборки…"
pkill -f "flutter_tools.snapshot" 2>/dev/null || true
pkill -f "xcodebuild" 2>/dev/null || true
sleep 1

echo "[$(ts)] 2/5 Удаляем DerivedData Runner (битый gRPC-кэш)…"
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* 2>/dev/null || true

if [[ "${REPAIR_DEEP:-}" == "1" ]]; then
  echo "[$(ts)] 3/5 flutter clean (глубокий режим)…"
  flutter clean
else
  echo "[$(ts)] 3/5 flutter pub get (без clean — быстрее)…"
fi
flutter pub get

echo "[$(ts)] 4/5 Переустановка Pods…"
cd ios
rm -rf Pods .symlinks
if [[ "${REPAIR_DEEP:-}" == "1" ]]; then
  echo "    pod install --repo-update (может занять 15–40 мин)…"
  pod install --repo-update
else
  echo "    pod install --no-repo-update (обычно 1–3 мин)…"
  pod install --no-repo-update
fi
cd ..

echo "[$(ts)] ✓ Среда сборки восстановлена"
