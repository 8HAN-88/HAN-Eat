#!/usr/bin/env bash
# Прокси /api/ и /health на haneat.app → backend (same-origin для Safari Web).
# На сервере: bash /root/HAN-Eat/scripts/patch_nginx_web_api_proxy.sh
set -euo pipefail

CONF="/etc/nginx/sites-available/haneat-web"

if [[ ! -f "$CONF" ]]; then
  echo "skip: $CONF not found"
  exit 0
fi

if grep -q 'location /api/' "$CONF"; then
  echo "ok: haneat.app /api/ proxy already present"
  nginx -t
  exit 0
fi

python3 <<'PY'
from pathlib import Path

conf = Path("/etc/nginx/sites-available/haneat-web")
text = conf.read_text()
block = """
    location = /health {
        proxy_pass http://127.0.0.1:8000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        client_max_body_size 64M;
    }
"""
marker = "    location / {"
if marker not in text:
    raise SystemExit("cannot find insertion point in haneat-web nginx config")
text = text.replace(marker, block + "\n" + marker, 1)
conf.write_text(text)
print("patched:", conf)
PY

nginx -t
systemctl reload nginx
echo "✓ haneat.app API same-origin proxy active"
