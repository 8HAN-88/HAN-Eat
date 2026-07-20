#!/usr/bin/env bash
# Упаковать build/web_root для загрузки на сервер без SSH (консоль Timeweb / SFTP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build/web_root"
OUT="${1:-/tmp/haneat-web.tgz}"

if [[ ! -f "${BUILD_DIR}/index.html" || ! -f "${BUILD_DIR}/app/main.dart.js" ]]; then
  echo "Нет ${BUILD_DIR}/app/main.dart.js — сначала: ./scripts/build_web_release.sh"
  exit 1
fi

# Archive layout expected by deploy_web_on_server_console.sh: web/index.html
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/web"
cp -a "${BUILD_DIR}/." "${TMP}/web/"
tar czf "${OUT}" -C "${TMP}" web

echo "✓ ${OUT} ($(du -h "${OUT}" | awk '{print $1}'))"
echo "  build=$(python3 -c "import json;print(json.load(open('${BUILD_DIR}/version.json'))['build_number'])")"
echo ""
echo "Дальше (SSH с Mac не работает):"
echo "  1) Загрузите ${OUT} на сервер в /root/haneat-web.tgz (SFTP / файлы Timeweb)"
echo "  2) В консоли Timeweb:"
echo "     bash /root/HAN-Eat/scripts/deploy_web_on_server_console.sh"
echo "     # или, если репо нет на сервере:"
echo "     WEB_ROOT=/var/www/haneat-web TGZ=/root/haneat-web.tgz bash -s <<'EOF'"
echo "     ... скопируйте тело scripts/deploy_web_on_server_console.sh ..."
echo "     EOF"
