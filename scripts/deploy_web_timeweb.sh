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
REMOTE_WEB_NEXT="${REMOTE_WEB_ROOT}.next"
REMOTE_WEB_PREV="${REMOTE_WEB_ROOT}.prev"
BUILD_DIR="${ROOT}/build/web"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
RSYNC_RETRIES="${RSYNC_RETRIES:-3}"

RSYNC_SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new -o ConnectTimeout=${SSH_CONNECT_TIMEOUT} -o ServerAliveInterval=10 -o ServerAliveCountMax=3"

echo "== HAN Eat: deploy web → ${SSH_USER}@${SSH_HOST}:${REMOTE_WEB_ROOT} =="

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}"
  exit 1
fi

if [[ ! -f "${BUILD_DIR}/index.html" ]]; then
  echo "Нет ${BUILD_DIR}/index.html — сначала: ./scripts/build_web_release.sh"
  exit 1
fi

echo "-- ssh preflight --"
if ! ssh -i "${SSH_KEY}" \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}" \
  -o BatchMode=yes \
  "${SSH_USER}@${SSH_HOST}" "echo SSH_OK" >/dev/null 2>&1; then
  echo "Не удалось подключиться по SSH к ${SSH_USER}@${SSH_HOST}."
  echo "Проверьте доступ к серверу/ключ и что SSH включен в панели Timeweb."
  echo "Быстрая проверка: ssh -i \"${SSH_KEY}\" ${SSH_USER}@${SSH_HOST}"
  echo "Если запускали включение serial через wget, используйте curl:"
  echo "  curl -fsSL https://st.timeweb.com/cloud-static/scripts/serial_enable.sh | bash"
  exit 1
fi

# assetlinks.json для TWA (если сгенерирован локально)
if [[ -f "${ROOT}/web/.well-known/assetlinks.json" ]]; then
  mkdir -p "${BUILD_DIR}/.well-known"
  cp "${ROOT}/web/.well-known/assetlinks.json" "${BUILD_DIR}/.well-known/"
fi

echo "-- rsync to staging (${REMOTE_WEB_NEXT}) --"
attempt=1
until rsync -avz --delete \
  --partial \
  --inplace \
  -e "${RSYNC_SSH}" \
  "${BUILD_DIR}/" \
  "${SSH_USER}@${SSH_HOST}:${REMOTE_WEB_NEXT}/"; do
  if [[ "${attempt}" -ge "${RSYNC_RETRIES}" ]]; then
    echo "rsync не удался после ${RSYNC_RETRIES} попыток."
    exit 1
  fi
  echo "rsync ошибка, повтор ${attempt}/${RSYNC_RETRIES} через 3с..."
  attempt=$((attempt + 1))
  sleep 3
done

echo "-- atomic switch live ← staging --"
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
  "${SSH_USER}@${SSH_HOST}" \
  "set -euo pipefail
   test -f '${REMOTE_WEB_NEXT}/index.html'
   test -f '${REMOTE_WEB_NEXT}/main.dart.js'
   test -f '${REMOTE_WEB_NEXT}/flutter_bootstrap.js'
   test -f '${REMOTE_WEB_NEXT}/version.json'
   rm -rf '${REMOTE_WEB_PREV}'
   if [ -d '${REMOTE_WEB_ROOT}' ]; then
     mv '${REMOTE_WEB_ROOT}' '${REMOTE_WEB_PREV}'
   fi
   mv '${REMOTE_WEB_NEXT}' '${REMOTE_WEB_ROOT}'
   chown -R www-data:www-data '${REMOTE_WEB_ROOT}' 2>/dev/null || true
   rm -rf '${REMOTE_WEB_PREV}'
  "

echo ""
echo "✓ Web deployed (atomic)"
echo "  URL: https://haneat.app"
echo "  PWA manifest: https://haneat.app/manifest.json"
echo "  Asset links:  https://haneat.app/.well-known/assetlinks.json"
echo ""
echo "Smoke: откройте https://haneat.app в Chrome → DevTools → Application → Manifest"
