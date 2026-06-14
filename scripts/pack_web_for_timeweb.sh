#!/usr/bin/env bash
# Упаковать build/web для загрузки на сервер без SSH (консоль Timeweb / SFTP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build/web"
OUT="${1:-/tmp/haneat-web.tgz}"

if [[ ! -f "${BUILD_DIR}/index.html" ]]; then
  echo "Нет ${BUILD_DIR}/index.html — сначала: ./scripts/build_web_release.sh"
  exit 1
fi

tar czf "${OUT}" -C "${ROOT}/build" web
echo "✓ ${OUT} ($(du -h "${OUT}" | awk '{print $1}'))"
echo ""
echo "Дальше (SSH не работает):"
echo "  1) Загрузите ${OUT} на сервер в /root/haneat-web.tgz (SFTP / файлы Timeweb)"
echo "  2) В консоли Timeweb:"
echo "     bash /root/HAN-Eat/scripts/deploy_web_on_server_console.sh"
