#!/usr/bin/env bash
# Применить nginx-фиксы для iPhone (HTTP 302 на /app/ + legacy /assets → /app/assets).
# Запуск с Mac, где SSH к серверу работает:
#   bash scripts/fix_ios_web_nginx.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="${HAN_SSH_KEY:-$HOME/.ssh/haneat_timeweb}"
SSH_USER="${HAN_SSH_USER:-root}"
SSH_HOST="${HAN_SSH_HOST:-89.19.216.60}"

echo "== upload patch =="
scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
  "${ROOT}/scripts/patch_nginx_web_api_proxy.sh" \
  "${SSH_USER}@${SSH_HOST}:/tmp/patch_nginx_web_api_proxy.sh"

echo "== apply + reload nginx =="
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
  "${SSH_USER}@${SSH_HOST}" \
  'bash /tmp/patch_nginx_web_api_proxy.sh && nginx -t && systemctl reload nginx && echo OK'

echo "== smoke =="
curl -sSI --max-time 15 https://haneat.app/ | head -12
echo "---"
curl -sSI --max-time 15 https://haneat.app/assets/assets/brand_logo.png | head -12
echo "---"
curl -sS -o /dev/null -w "app:%{http_code}\n" --max-time 15 https://haneat.app/app/
echo "✓ done — на iPhone открой: https://haneat.app/app/"
