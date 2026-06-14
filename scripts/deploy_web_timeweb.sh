#!/usr/bin/env bash
# Деплой Flutter Web (PWA) на haneat.app.
#
# Перед первым деплоем на сервере:
#   bash scripts/setup_nginx_haneat_web.sh
#   certbot --nginx -d haneat.app -d www.haneat.app
#
# С Mac:
#   ./scripts/build_web_release.sh
#   bash scripts/deploy_web_timeweb.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="${HAN_SSH_KEY:-$HOME/.ssh/haneat_timeweb}"
SSH_USER="${HAN_SSH_USER:-root}"
SSH_HOST="${HAN_SSH_HOST:-89.19.216.60}"
REMOTE_WEB_ROOT="${HAN_WEB_ROOT:-/var/www/haneat-web}"
BUILD_DIR="${ROOT}/build/web"

RSYNC_SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new"

echo "== HAN Eat: deploy web → ${SSH_USER}@${SSH_HOST}:${REMOTE_WEB_ROOT} =="

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}"
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/index.html" ]]; then
  echo "Нет ${BUILD_DIR}/index.html — сначала: ./scripts/build_web_release.sh"
  exit 1
fi

# assetlinks.json для TWA (если сгенерирован локально)
if [[ -f "${ROOT}/web/.well-known/assetlinks.json" ]]; then
  mkdir -p "${BUILD_DIR}/.well-known"
  cp "${ROOT}/web/.well-known/assetlinks.json" "${BUILD_DIR}/.well-known/"
fi

echo "-- rsync build/web --"
rsync -avz --delete \
  -e "${RSYNC_SSH}" \
  "${BUILD_DIR}/" \
  "${SSH_USER}@${SSH_HOST}:${REMOTE_WEB_ROOT}/"

echo "-- remote permissions --"
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
  "${SSH_USER}@${SSH_HOST}" \
  "chown -R www-data:www-data '${REMOTE_WEB_ROOT}' 2>/dev/null || true"

echo ""
echo "✓ Web deployed"
echo "  URL: https://haneat.app"
echo "  PWA manifest: https://haneat.app/manifest.json"
echo "  Asset links:  https://haneat.app/.well-known/assetlinks.json"
echo ""
echo "Smoke: откройте https://haneat.app в Chrome → DevTools → Application → Manifest"
