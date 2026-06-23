#!/usr/bin/env bash
# Добавляет nginx location для SSE /api/v1/realtime/stream (если ещё нет).
# На сервере:
#   bash /root/HAN-Eat/scripts/patch_nginx_realtime_sse.sh
set -euo pipefail

CONF="/etc/nginx/sites-available/haneat-api"

if [[ ! -f "$CONF" ]]; then
  echo "skip: $CONF not found"
  exit 0
fi

if grep -q 'realtime/stream' "$CONF"; then
  echo "ok: realtime SSE location already present"
  nginx -t
  exit 0
fi

python3 <<'PY'
from pathlib import Path

conf = Path("/etc/nginx/sites-available/haneat-api")
text = conf.read_text()
block = """
    location = /api/v1/realtime/stream {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        chunked_transfer_encoding off;
    }
"""
marker = "    location ~ ^/api/v1/chats/[0-9]+/stream"
if marker in text:
    text = text.replace(marker, block + "\n" + marker, 1)
elif "    location / {" in text:
    text = text.replace("    location / {", block + "\n    location / {", 1)
else:
    raise SystemExit("cannot find insertion point in nginx config")
conf.write_text(text)
print("patched:", conf)
PY

nginx -t
systemctl reload nginx
echo "✓ nginx realtime SSE location active"
