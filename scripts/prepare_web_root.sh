#!/usr/bin/env bash
# Собирает публичный корень сайта:
#   /           — HTML auth gate (без Flutter/CanvasKit)
#   /app/       — Flutter Web (base-href /app/)
#   /version.json — для автообновления
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="${ROOT}/build/web"
OUT_DIR="${ROOT}/build/web_root"
BUILD_ID="${1:-}"

if [[ ! -f "${WEB_DIR}/index.html" ]]; then
  echo "prepare_web_root: нет ${WEB_DIR}/index.html"
  exit 1
fi

if [[ -z "${BUILD_ID}" ]]; then
  BUILD_ID="$(python3 - <<PY
import json, pathlib
p = pathlib.Path("${WEB_DIR}/version.json")
print(json.loads(p.read_text(encoding="utf-8")).get("build_number", ""))
PY
)"
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/app"

# Flutter app under /app/
cp -a "${WEB_DIR}/." "${OUT_DIR}/app/"

# Root version.json for WebAppUpdateService (/version.json)
cp -f "${WEB_DIR}/version.json" "${OUT_DIR}/version.json"

# TWA asset links stay at domain root
if [[ -d "${WEB_DIR}/.well-known" ]]; then
  mkdir -p "${OUT_DIR}/.well-known"
  cp -a "${WEB_DIR}/.well-known/." "${OUT_DIR}/.well-known/"
fi

# HTML auth gate at site root — iPhone must never cold-boot into /app/ from "/".
# Keep <base href="/app/"> so relative icon/manifest URLs resolve under /app/.
cp -f "${OUT_DIR}/app/index.html" "${OUT_DIR}/index.html"
cp -f "${OUT_DIR}/app/index.html" "${OUT_DIR}/login.html"

echo "✓ web_root ready (build=${BUILD_ID}) → ${OUT_DIR} (HTML auth at / and /login.html)"
