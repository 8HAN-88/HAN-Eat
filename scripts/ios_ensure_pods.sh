#!/usr/bin/env bash
# Быстрый pod install: без обновления CDN Specs (иначе зависает на 10–30+ мин).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"

cd "$ROOT"
flutter pub get >/dev/null

cd "$IOS"
if [[ ! -f Podfile.lock ]]; then
  echo "Нет Podfile.lock — полный pod install (может занять долго)…"
  pod install
  exit 0
fi

mkdir -p Pods
# pub get мог удалить Manifest.lock — восстанавливаем, если Pods уже установлены.
if [[ ! -f Pods/Manifest.lock ]] && [[ -d Pods/Target\ Support\ Files/Pods-Runner ]]; then
  echo "Восстанавливаем Pods/Manifest.lock из Podfile.lock…"
  cp Podfile.lock Pods/Manifest.lock
fi

if ! diff -q Podfile.lock Pods/Manifest.lock >/dev/null 2>&1; then
  echo "Podfile.lock изменился — pod install --no-repo-update…"
  pod install --no-repo-update
else
  echo "Pods уже синхронизированы — pod install пропущен."
fi

"$ROOT/scripts/ios_restore_pods_from_cache.sh"

# Flutter запускает pod install, если нет build/pod_inputs.fingerprint — обновляем без CDN.
FINGERPRINT="$ROOT/build/pod_inputs.fingerprint"
PODHELPER="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}/packages/flutter_tools/bin/podhelper.rb"
if [[ ! -f "$FINGERPRINT" ]] && [[ -f "$PODHELPER" ]]; then
  python3 - "$FINGERPRINT" "$IOS/Runner.xcodeproj/project.pbxproj" "$IOS/Podfile" "$PODHELPER" <<'PY'
import hashlib, json, os, sys
out, *paths = sys.argv[1:]
files = {}
for p in paths:
    ap = os.path.abspath(p)
    with open(ap, "rb") as f:
        files[ap] = hashlib.md5(f.read()).hexdigest()
with open(out, "w") as f:
    json.dump({"files": files}, f)
PY
  echo "✓ pod_inputs.fingerprint создан (flutter build не дергает CDN)"
fi

echo "✓ CocoaPods готов"
