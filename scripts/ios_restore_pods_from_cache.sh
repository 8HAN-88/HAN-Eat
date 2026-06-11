#!/usr/bin/env bash
# Восстанавливает пустые/битые Pods из ~/Library/Caches/CocoaPods (CDN иногда не докачивает).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PODS="$ROOT/ios/Pods"
CACHE="$HOME/Library/Caches/CocoaPods/Pods/Release"

if [[ ! -d "$PODS" ]]; then
  exit 0
fi

fixed="$(python3 - "$PODS" "$CACHE" <<'PY'
import glob, os, shutil, sys

pods_dir, cache_root = sys.argv[1:3]
skip = {"Headers", "Local Podspecs", "Target Support Files", "Pods.xcodeproj"}
fixed = 0
for name in os.listdir(pods_dir):
    if name in skip or name.startswith("."):
        continue
    path = os.path.join(pods_dir, name)
    if not os.path.isdir(path):
        continue
    size = sum(
        os.path.getsize(os.path.join(r, f))
        for r, _, fs in os.walk(path)
        for f in fs
    )
    if size > 4096:
        continue
    matches = glob.glob(os.path.join(cache_root, name, "*"))
    if not matches:
        continue
    shutil.rmtree(path)
    shutil.copytree(matches[0], path)
    fixed += 1
print(fixed)
if fixed:
    print(f"✓ Восстановлено pods из cache: {fixed}", file=sys.stderr)
PY
)"
fixed="${fixed%%$'\n'*}"

if [[ "${fixed:-0}" -gt 0 ]]; then
  echo "Перегенерация Pods.xcodeproj после восстановления…"
  (cd "$ROOT/ios" && pod install --no-repo-update >/dev/null)
  echo "✓ Pods.xcodeproj обновлён"
fi
