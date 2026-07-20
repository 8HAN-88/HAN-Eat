#!/usr/bin/env bash
# Деплой web/PWA НА СЕРВЕРЕ (Timeweb → Консоль в браузере).
# Нужен архив /root/haneat-web.tgz (scripts/pack_web_for_timeweb.sh) или URL в HANEAT_WEB_TGZ_URL.
set -euo pipefail

WEB_ROOT="${HAN_WEB_ROOT:-/var/www/haneat-web}"
TGZ="${HANEAT_WEB_TGZ:-/root/haneat-web.tgz}"
TMP="/tmp/haneat-web-deploy-$$"

echo "== HAN Eat: deploy web (server console) =="

if [[ -n "${HANEAT_WEB_TGZ_URL:-}" ]]; then
  echo "-- download ${HANEAT_WEB_TGZ_URL} --"
  curl -fsSL "${HANEAT_WEB_TGZ_URL}" -o "${TGZ}"
fi

if [[ ! -f "${TGZ}" ]]; then
  echo "Нет ${TGZ}. Загрузите haneat-web.tgz в /root/ или задайте HANEAT_WEB_TGZ_URL"
  exit 1
fi

mkdir -p "${TMP}"
tar xzf "${TGZ}" -C "${TMP}"
if [[ ! -f "${TMP}/web/index.html" || ! -f "${TMP}/web/app/main.dart.js" ]]; then
  echo "Архив должен содержать web/index.html и web/app/main.dart.js"
  exit 1
fi

NEXT="${WEB_ROOT}.next"
PREV="${WEB_ROOT}.prev"
rm -rf "${NEXT}"
mkdir -p "${NEXT}"
rsync -a --delete "${TMP}/web/" "${NEXT}/"
chown -R www-data:www-data "${NEXT}" 2>/dev/null || true
rm -rf "${TMP}"

# Atomic swap (same idea as deploy_web_timeweb.sh).
if [[ -d "${WEB_ROOT}" ]]; then
  rm -rf "${PREV}"
  mv "${WEB_ROOT}" "${PREV}"
fi
mv "${NEXT}" "${WEB_ROOT}"
rm -rf "${PREV}"

# nginx: no-cache для bootstrap, version, icons, main.dart.js
if [[ -f /etc/nginx/sites-available/haneat-web ]]; then
  if ! grep -q 'location \^~ /icons/' /etc/nginx/sites-available/haneat-web; then
    python3 - <<'PY'
from pathlib import Path
p = Path("/etc/nginx/sites-available/haneat-web")
text = p.read_text()
block = """    location ^~ /icons/ {
        add_header Cache-Control \"no-cache, must-revalidate\";
        try_files $uri =404;
    }

"""
if "location ^~ /icons/" not in text:
    text = text.replace("    location = /main.dart.js {", block + "    location = /main.dart.js {")
    p.write_text(text)
PY
    nginx -t && systemctl reload nginx
  fi
fi

echo ""
echo "✓ Web deployed → ${WEB_ROOT}"
curl -sf "http://127.0.0.1/version.json" 2>/dev/null | head -1 || true
echo ""
echo "Проверка: https://haneat.app/version.json"
