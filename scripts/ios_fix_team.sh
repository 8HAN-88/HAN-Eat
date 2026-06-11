#!/usr/bin/env bash
# Team задаётся в ios/Flutter/Team.xcconfig — убираем дубли из pbxproj,
# чтобы Xcode не перезаписывал Team на устаревшее значение.
set -euo pipefail
cd "$(dirname "$0")/.."

PBX="ios/Runner.xcodeproj/project.pbxproj"
if [[ ! -f "$PBX" ]]; then
  exit 0
fi

if grep -q 'DEVELOPMENT_TEAM' "$PBX"; then
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i '/DEVELOPMENT_TEAM = /d' "$PBX"
  else
    sed -i '' '/DEVELOPMENT_TEAM = /d' "$PBX"
  fi
  echo "✓ Убран DEVELOPMENT_TEAM из project.pbxproj (используется Team.xcconfig)"
fi
