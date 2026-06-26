#!/usr/bin/env bash
# Генерация иконок iOS + Android из квадратного PNG/JPEG (1024×1024).
# По умолчанию увеличивает логотип (ZOOM) и обрезает по центру — буквы крупнее на иконке.
#
#   bash scripts/generate_app_icons.sh [source.png]
#   ZOOM=1.55 bash scripts/generate_app_icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW="${1:-$ROOT/assets/app_icon_raw.png}"
IOS_DIR="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ASSETS="$ROOT/assets/app_icon_source.png"
ZOOM="${ZOOM:-1.52}"

if [[ ! -f "$RAW" ]]; then
  echo "Source not found: $RAW"
  exit 1
fi

echo "== App icons from: $RAW (zoom ${ZOOM}x) =="

mkdir -p "$(dirname "$ASSETS")" "$(dirname "$RAW")"
if [[ "$RAW" != "$ROOT/assets/app_icon_raw.png" ]]; then
  cp "$RAW" "$ROOT/assets/app_icon_raw.png"
  RAW="$ROOT/assets/app_icon_raw.png"
fi

python3 - "$RAW" "$ASSETS" "$ZOOM" <<'PY'
import sys
from PIL import Image

src, dst, zoom = sys.argv[1], sys.argv[2], float(sys.argv[3])
size = 1024

img = Image.open(src).convert("RGBA")
w, h = img.size
nw, nh = int(w * zoom), int(h * zoom)
img = img.resize((nw, nh), Image.Resampling.LANCZOS)
left = (nw - size) // 2
top = (nh - size) // 2
img = img.crop((left, top, left + size, top + size))
# Чёрный фон, если по краям прозрачность
bg = Image.new("RGBA", (size, size), (0, 0, 0, 255))
bg.paste(img, (0, 0), img)
bg.convert("RGB").save(dst, "PNG")
PY

resize() {
  local px="$1"
  local out="$2"
  sips -z "$px" "$px" "$ASSETS" --out "$out" >/dev/null
}

echo "-- iOS AppIcon.appiconset --"
resize 40  "$IOS_DIR/Icon-App-20x20@2x.png"
resize 60  "$IOS_DIR/Icon-App-20x20@3x.png"
resize 20  "$IOS_DIR/Icon-App-20x20@1x.png"
resize 29  "$IOS_DIR/Icon-App-29x29@1x.png"
resize 58  "$IOS_DIR/Icon-App-29x29@2x.png"
resize 87  "$IOS_DIR/Icon-App-29x29@3x.png"
resize 40  "$IOS_DIR/Icon-App-40x40@1x.png"
resize 80  "$IOS_DIR/Icon-App-40x40@2x.png"
resize 120 "$IOS_DIR/Icon-App-40x40@3x.png"
resize 120 "$IOS_DIR/Icon-App-60x60@2x.png"
resize 180 "$IOS_DIR/Icon-App-60x60@3x.png"
resize 76  "$IOS_DIR/Icon-App-76x76@1x.png"
resize 152 "$IOS_DIR/Icon-App-76x76@2x.png"
resize 167 "$IOS_DIR/Icon-App-83.5x83.5@2x.png"
resize 1024 "$IOS_DIR/Icon-App-1024x1024@1x.png"

echo "-- Android mipmap --"
resize 48  "$ROOT/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
resize 72  "$ROOT/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
resize 96  "$ROOT/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
resize 144 "$ROOT/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

WEB_ICONS="$ROOT/web/icons"
mkdir -p "$WEB_ICONS"
echo "-- PWA / web icons --"
resize 192 "$WEB_ICONS/Icon-192.png"
resize 512 "$WEB_ICONS/Icon-512.png"
cp "$WEB_ICONS/Icon-192.png" "$WEB_ICONS/Icon-maskable-192.png"
cp "$WEB_ICONS/Icon-512.png" "$WEB_ICONS/Icon-maskable-512.png"
cp "$WEB_ICONS/Icon-192.png" "$ROOT/web/favicon.png"
sips -z 180 180 "$ASSETS" --out "$WEB_ICONS/Icon-180.png" >/dev/null 2>&1 || cp "$WEB_ICONS/Icon-192.png" "$WEB_ICONS/Icon-180.png"

echo "Done. Rebuild: ./scripts/run_ios_physical.sh"
echo "  Web: ./scripts/build_web_release.sh && bash scripts/deploy_web_timeweb.sh"
