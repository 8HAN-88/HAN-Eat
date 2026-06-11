#!/usr/bin/env bash
# Release-сборка iOS с production API и Google OAuth из .env.
# Использование: ./scripts/build_ios_release.sh [API_BASE]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${1:-}"

cd "$ROOT"
_build() {
  if [[ -n "$API_BASE" ]]; then
    HANEAT_API_BASE="$API_BASE" ./scripts/with_dart_defines.sh flutter build ipa --release
  else
    ./scripts/with_dart_defines.sh flutter build ipa --release
  fi
}
if ! _build; then
  echo ""
  echo "⚠️  IPA не собран. Часто не хватает сертификата «iOS Distribution»."
  echo "   Xcode → Settings → Accounts → Download Manual Profiles"
  echo "   open build/ios/archive/Runner.xcarchive"
  exit 1
fi

if ! [[ -d build/ios/ipa ]] && [[ -d build/ios/archive/Runner.xcarchive ]]; then
  echo "⚠️  IPA не в build/ios/ipa — откройте архив в Xcode:"
  echo "   open build/ios/archive/Runner.xcarchive"
  exit 0
fi

if [[ ! -d build/ios/ipa ]] || [[ -z "$(find build/ios/ipa -name '*.ipa' 2>/dev/null)" ]]; then
  echo "⚠️  Папка build/ios/ipa пуста — используйте Runner.xcarchive в Xcode."
  exit 1
fi

echo "✓ IPA: build/ios/ipa"
