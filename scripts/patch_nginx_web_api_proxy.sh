#!/usr/bin/env bash
# Прокси /api/ и /health на haneat.app → backend (same-origin для Safari Web)
# и cache policy, при которой Flutter Web всегда показывает последний deploy.
# На сервере: bash /root/HAN-Eat/scripts/patch_nginx_web_api_proxy.sh
set -euo pipefail

CONF="/etc/nginx/sites-available/haneat-web"

if [[ ! -f "$CONF" ]]; then
  echo "skip: $CONF not found — run scripts/setup_nginx_haneat_web.sh"
  exit 1
fi

python3 <<'PY'
import re
from pathlib import Path

conf = Path("/etc/nginx/sites-available/haneat-web")
text = conf.read_text()

managed = """
    # BEGIN HAN-EAT MANAGED CACHE/API
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

    # Force app shell revalidation for iOS/PWA standalone mode.
    location = / {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files /index.html =404;
    }

    location = /index.html {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    location ~* ^/(flutter_service_worker\\.js|flutter_bootstrap\\.js|version\\.json|manifest\\.json|flutter\\.js)$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # ^~ keeps query suffixes from hitting immutable regex location.
    location ^~ /main.dart.js {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    location ^~ /icons/ {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }

    location ^~ /assets/ {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }

    location ^~ /canvaskit/ {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }
    # END HAN-EAT MANAGED CACHE/API
"""

legacy_patterns = [
    r"\n\s*location\s*=\s*/health\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*/api/\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*~\*\s*\^/\(flutter_service_worker\\\.js\|flutter_bootstrap\\\.js\|version\\\.json\)\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*\^~\s*/main\.dart\.js\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*\^~\s*/icons/\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*\^~\s*/assets/\s*\{.*?\n\s*\}\n",
    r"\n\s*location\s*\^~\s*/canvaskit/\s*\{.*?\n\s*\}\n",
]

def patch_server_block(block_text: str) -> str:
    patched = block_text

    patched = re.sub(
        r"\n\s*# BEGIN HAN-EAT MANAGED CACHE/API.*?# END HAN-EAT MANAGED CACHE/API\n",
        "\n",
        patched,
        flags=re.DOTALL,
    )
    for pattern in legacy_patterns:
        patched = re.sub(pattern, "\n", patched, flags=re.DOTALL)

    static_marker = "    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|wasm)$ {"
    app_marker = "    location / {"
    if static_marker in patched:
        patched = patched.replace(static_marker, managed + "\n" + static_marker, 1)
    elif app_marker in patched:
        patched = patched.replace(app_marker, managed + "\n" + app_marker, 1)
    else:
        patched = patched.replace("\n}\n", "\n" + managed + "\n}\n", 1)
    return patched

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
    print("ok: config already up to date")
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
echo "Verifying Flutter assets revalidate..."
curl -sfI "https://haneat.app/assets/AssetManifest.bin.json" | grep -i "cache-control" | grep -qi "no-cache"
echo "✓ haneat.app Flutter asset cache policy active"
