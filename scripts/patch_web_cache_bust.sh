#!/usr/bin/env bash
# Подставляет ?v=… в main.dart.js, иконки, manifest — обход nginx immutable-cache.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="${ROOT}/build/web"
BOOTSTRAP="${WEB_DIR}/flutter_bootstrap.js"
INDEX_HTML="${WEB_DIR}/index.html"
MANIFEST="${WEB_DIR}/manifest.json"
VERSION_FILE="${WEB_DIR}/version.json"

if [[ ! -f "$BOOTSTRAP" ]]; then
  echo "patch_web_cache_bust: нет $BOOTSTRAP (сначала flutter build web)"
  exit 1
fi

BUILD_ID="${1:-$(date -u +%Y%m%d%H%M%S)}"
MAIN_PATH="main.dart.js?v=${BUILD_ID}"
ICON_QS="?v=${BUILD_ID}"

python3 - <<PY
import json
import pathlib
import re

build_id = "${BUILD_ID}"
main_path = "${MAIN_PATH}"
icon_qs = "${ICON_QS}"

bootstrap = pathlib.Path("${BOOTSTRAP}")
text = bootstrap.read_text(encoding="utf-8")
text, n = re.subn(
    r'"mainJsPath":"main\.dart\.js[^"]*"',
    f'"mainJsPath":"{main_path}"',
    text,
    count=1,
)
if n != 1:
    raise SystemExit(f"patch_web_cache_bust: mainJsPath not patched ({n})")
bootstrap.write_text(text, encoding="utf-8")

index_html = pathlib.Path("${INDEX_HTML}")
if index_html.exists():
    html = index_html.read_text(encoding="utf-8")
    html = re.sub(
        r'href="icons/Icon-(\d+)\.png(\?v=[^"]*)?"',
        lambda m: f'href="icons/Icon-{m.group(1)}.png{icon_qs}"',
        html,
    )
    html = re.sub(
        r'href="favicon\.png(\?v=[^"]*)?"',
        f'href="favicon.png{icon_qs}"',
        html,
    )
    html = re.sub(
        r'href="manifest\.json(\?v=[^"]*)?"',
        f'href="manifest.json{icon_qs}"',
        html,
    )
    if 'id="boot-status"' in html:
        html, n = re.subn(
            r'(<div id="boot-status"[^>]*>)Загрузка…',
            rf'\1Загрузка… · {build_id}',
            html,
            count=1,
        )
    index_html.write_text(html, encoding="utf-8")

manifest = pathlib.Path("${MANIFEST}")
if manifest.exists():
    data = json.loads(manifest.read_text(encoding="utf-8"))
    for icon in data.get("icons", []):
        src = icon.get("src", "")
        base = src.split("?")[0]
        icon["src"] = f"{base}{icon_qs}"
    manifest.write_text(
        json.dumps(data, ensure_ascii=False, indent=4) + "\n",
        encoding="utf-8",
    )

version = pathlib.Path("${VERSION_FILE}")
if version.exists():
    data = json.loads(version.read_text(encoding="utf-8"))
    data["build_number"] = build_id
    version.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")

print(f"✓ cache bust build={build_id}")
PY
