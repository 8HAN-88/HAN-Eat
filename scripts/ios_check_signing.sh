#!/usr/bin/env bash
# Быстрая проверка подписи (без полной сборки).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${HAN_DEVELOPMENT_TEAM:-94NCHYWGB8}"
BUNDLE_ID="${HAN_BUNDLE_ID:-com.haneat.app}"

echo "== Проверка подписи iOS =="
echo "Team: ${TEAM_ID}  Bundle: ${BUNDLE_ID}"
echo ""

chmod +x ./scripts/ios_sync_profiles.sh 2>/dev/null || true
./scripts/ios_sync_profiles.sh 2>/dev/null || true

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  echo "❌ Нет сертификата Apple Development в Keychain."
  exit 1
fi
echo "✓ Сертификат в Keychain"

profiles_dir="${HOME}/Library/MobileDevice/Provisioning Profiles"
profile_count=0
if [[ -d "$profiles_dir" ]]; then
  profile_count=$(find "$profiles_dir" -name '*.mobileprovision' 2>/dev/null | wc -l | tr -d ' ')
fi
echo "Provisioning profiles: ${profile_count}"

app="build/ios/iphoneos/Runner.app"
if [[ -d "$app" ]]; then
  if codesign -dv "$app" 2>/dev/null | grep -q "Authority=Apple"; then
    echo "✓ Runner.app подписан"
    exit 0
  fi
  echo "⚠️  Runner.app есть, но НЕ подписан (нужен Xcode Run)"
fi

# Лёгкая проверка без полной сборки
sign_hint=$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -showBuildSettings -destination 'generic/platform=iOS' 2>&1 \
  | grep -E "No Account for Team|No profiles for" || true)

if [[ -n "$sign_hint" ]] || [[ "$profile_count" == "0" ]]; then
  echo ""
  echo "❌ Подпись не готова для установки на iPhone."
  echo ""
  echo "Сделайте ОДИН раз в Xcode (2 мин):"
  echo "  open ios/Runner.xcworkspace"
  echo ""
  echo "  1. Xcode → Settings (⌘,) → Accounts"
  echo "     Если пусто: + → Apple ID → airat8446@gmail.com"
  echo "  2. Runner → Signing & Capabilities"
  echo "     Team: Airat Hadiev (94NCHYWGB8)"
  echo "     ✓ Automatically manage signing"
  echo "  3. iPhone по USB, сверху выберите iPhone → ▶ Run"
  echo "  4. Дождитесь Build Succeeded"
  echo ""
  echo "Потом снова: ./scripts/run_ios_physical.sh"
  exit 1
fi

echo "✓ Подпись выглядит готовой"
