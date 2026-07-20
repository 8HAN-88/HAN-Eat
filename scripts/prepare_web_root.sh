#!/usr/bin/env bash
# Собирает публичный корень сайта:
#   /           — мгновенный редирект на /app/ (meta refresh, работает без JS)
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

# Tiny root shell: meta-refresh works even when mobile browsers block/skip JS.
cat > "${OUT_DIR}/index.html" <<EOF
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover">
  <meta name="theme-color" content="#0F1319">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta http-equiv="refresh" content="0;url=/app/?v=${BUILD_ID}">
  <title>HAN Eat</title>
  <style>
    html, body { margin: 0; height: 100%; background: #0F1319; }
  </style>
  <script>
    location.replace('/app/?v=${BUILD_ID}&_cb=' + Date.now());
  </script>
</head>
<body></body>
</html>
EOF

echo "✓ web_root ready (build=${BUILD_ID}) → ${OUT_DIR}"
