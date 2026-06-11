#!/usr/bin/env bash
# Копирует .mobileprovision из Xcode UserData в ~/Library/MobileDevice/Provisioning Profiles/
set -euo pipefail

src="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
dst="${HOME}/Library/MobileDevice/Provisioning Profiles"

if [[ ! -d "$src" ]]; then
  echo "⚠️  Нет профилей в Xcode UserData ($src)"
  exit 0
fi

mkdir -p "$dst"
count=0
while IFS= read -r -d '' f; do
  cp -f "$f" "$dst/$(basename "$f")"
  count=$((count + 1))
done < <(find "$src" -name '*.mobileprovision' -print0 2>/dev/null)

echo "✓ Синхронизировано provisioning profiles: ${count} → $dst"
