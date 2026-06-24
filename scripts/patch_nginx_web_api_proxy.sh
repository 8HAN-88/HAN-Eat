#!/usr/bin/env bash
# Прокси /api/ и /health на haneat.app → backend (same-origin для Safari Web).
# На сервере: bash /root/HAN-Eat/scripts/patch_nginx_web_api_proxy.sh
set -euo pipefail

CONF="/etc/nginx/sites-available/haneat-web"

if [[ ! -f "$CONF" ]]; then
  echo "skip: $CONF not found — run scripts/setup_nginx_haneat_web.sh"
  exit 1
fi

python3 <<'PY'
import re
import subprocess
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

def patch_server_block(block_text: str) -> str:
    if "location /api/" in block_text:
        return block_text
    marker = "    location / {"
    if marker not in block_text:
        raise SystemExit("cannot find insertion point in a server block")
    return block_text.replace(marker, block + "\n" + marker, 1)

parts = re.split(r"(?=\nserver\s*\{)", text)
if len(parts) == 1:
    parts = [text]

out = []
changed = False
for part in parts:
    if "server_name" in part and "haneat.app" in part:
        patched = patch_server_block(part)
        changed = changed or patched != part
        out.append(patched)
    else:
        out.append(part)

new_text = "".join(out)
if changed:
    conf.write_text(new_text)
    print("patched:", conf)
else:
    print("ok: all haneat.app server blocks already have /api/ proxy")
PY

nginx -t
systemctl reload nginx

echo "Verifying HTTPS /health returns JSON..."
for host in haneat.app www.haneat.app; do
  body="$(curl -sf "https://${host}/health" || true)"
  if [[ "$body" != *'"status"'* ]]; then
    echo "FAIL: https://${host}/health is not API JSON (nginx proxy missing on HTTPS?)"
    echo "Run: bash scripts/setup_nginx_haneat_web.sh && certbot --nginx -d haneat.app -d www.haneat.app"
    exit 1
  fi
  echo "  OK https://${host}/health"
done
echo "✓ haneat.app API same-origin proxy active"
