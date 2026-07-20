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
    if "__HAN_BUILD_ID__" in html:
        html = html.replace("__HAN_BUILD_ID__", build_id)
    # Idempotent: already-patched index from a prior pass is OK.
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
    index_html.write_text(html, encoding="utf-8")

manifest = pathlib.Path("${MANIFEST}")
if manifest.exists():
    data = json.loads(manifest.read_text(encoding="utf-8"))
    # PWA must open HTML auth at /, not cold-boot Flutter under /app/.
    data["start_url"] = f"/?v={build_id}"
    data["scope"] = "/"
    data["id"] = "https://haneat.app/"
    for icon in data.get("icons", []):
        src = icon.get("src", "")
        base = src.split("?")[0]
        if not base.startswith("/") and not base.startswith("http"):
            base = f"/app/{base.lstrip('./')}"
        elif base.startswith("icons/"):
            base = f"/app/{base}"
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


# Flutter sometimes emits an empty {} build entry alongside dart2js; drop it.
text = bootstrap.read_text(encoding="utf-8")
cfg_m = re.search(r'_flutter\.buildConfig = (\{.*?\});', text)
if cfg_m:
    cfg = json.loads(cfg_m.group(1))
    builds = [
        b for b in cfg.get("builds", [])
        if isinstance(b, dict)
        and b.get("compileTarget") == "dart2js"
        and b.get("mainJsPath")
    ]
    if not builds:
        raise SystemExit("patch_web_cache_bust: no dart2js build in buildConfig")
    cfg["builds"] = builds
    cfg["useLocalCanvasKit"] = True
    text = text[:cfg_m.start()] + "_flutter.buildConfig = " + json.dumps(cfg, separators=(",", ":")) + ";" + text[cfg_m.end():]

# Force canvaskit-only boot and disable Flutter service worker registration.
# SW + mid-deploy asset gaps are a common Safari white-screen trigger.
load_re = re.compile(
    r'_flutter\.loader\.load\(\{.*?\n\}\);',
    re.DOTALL,
)
load_block = """_flutter.loader.load({
  config: {
    renderer: "canvaskit",
    useLocalCanvasKit: true,
    canvasKitBaseUrl: "canvaskit/",
  },
});"""
text2, load_n = load_re.subn(load_block, text, count=1)
if load_n != 1:
    raise SystemExit(f"patch_web_cache_bust: loader.load not patched ({load_n})")
bootstrap.write_text(text2, encoding="utf-8")

print(f"✓ cache bust build={build_id}")
PY
