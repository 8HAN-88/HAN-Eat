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

    # Shared /reel/:id and /post/:id — OG HTML for Telegram/iMessage, then hop to /app/.
    location ~ ^/(reel|post)/([0-9]+)/?$ {
        proxy_pass http://127.0.0.1:8000/api/v1/og/$1/$2;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        add_header Cache-Control "public, max-age=300";
    }

    # One-shot Safari/PWA recovery: wipe Cache API + storage + SW, then HTML login.
    location = /fresh {
        add_header Clear-Site-Data '"cache", "storage", "executionContexts"' always;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Pragma "no-cache" always;
        return 302 /app/?go=1&fresh=1;
    }

    # Tiny JS beacon used by app shell to prove the device reached the new build.
    location = /boot-ping {
        add_header Cache-Control "no-store" always;
        add_header Access-Control-Allow-Origin "*" always;
        return 204;
    }

    # HTML auth gate at site root (no Flutter).
    # Do NOT send Clear-Site-Data here — on iPhone Safari it can hang the tab
    # for ~60s (black screen → «сервер перестал отвечать») and never finish
    # the navigation. Nuclear wipe stays only on /fresh.
    location = / {
        try_files /index.html =404;
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Pragma "no-cache" always;
    }

    location = /index.html {
        try_files /index.html =404;
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Pragma "no-cache" always;
    }

    location = /login.html {
        try_files /login.html =404;
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        add_header Pragma "no-cache" always;
    }

    location = /login {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0" always;
        return 302 /login.html;
    }

    location = /version.json {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # Flutter app shell under /app/
    location = /app {
        return 302 /app/;
    }

    location = /app/ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files /app/index.html =404;
    }

    location = /app/index.html {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    location ~* ^/app/(flutter_service_worker\\.js|flutter_bootstrap\\.js|version\\.json|manifest\\.json|flutter\\.js)$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # Deferred parts: main.dart.js_*.part.js — SAME unversioned URL across deploys.
    # Longer ^~ prefix than /app/main.dart.js so parts are not long-cached with the
    # entrypoint (stale part.js + new main = black→white Safari boot).
    location ^~ /app/main.dart.js_ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # Entrypoint main.dart.js?v=BUILD — safe to cache by URL.
    # no-store forced every phone to re-download ~3MB and often died mid-transfer.
    location ^~ /app/main.dart.js {
        add_header Cache-Control "public, max-age=604800";
        try_files $uri =404;
    }

    location ^~ /app/icons/ {
        add_header Cache-Control "public, max-age=604800";
        try_files $uri =404;
    }

    location ^~ /app/assets/ {
        add_header Cache-Control "public, max-age=604800";
        try_files $uri =404;
    }

    # CanvasKit is engine-tied; long cache after first successful phone download.
    location ^~ /app/canvaskit/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    # SPA routes under /app/feed, /app/login, ...
    location ^~ /app/ {
        add_header Cache-Control "no-cache";
        try_files $uri $uri/ /app/index.html;
    }

    # Stuck Safari/YaBrowser shells still request legacy root asset paths.
    # ^~ beats the immutable regex location that would otherwise 404.
    location ^~ /assets/ { return 302 /app$request_uri; }
    location ^~ /canvaskit/ { return 302 /app$request_uri; }
    location ^~ /icons/ { return 302 /app$request_uri; }
    location ^~ /main.dart.js { return 302 /app$request_uri; }
    location = /flutter_bootstrap.js { return 302 /app/flutter_bootstrap.js; }
    location = /flutter.js { return 302 /app/flutter.js; }
    location = /flutter_service_worker.js { return 302 /app/flutter_service_worker.js; }
    location = /manifest.json { return 302 /app/manifest.json; }
    location = /favicon.png { return 302 /app/favicon.png; }
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

    gzip_block = """
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/manifest+json
        application/wasm
        image/svg+xml;
"""
    patched = re.sub(
        r"\n\s*gzip on;\n\s*gzip_vary on;\n\s*gzip_min_length 1024;\n\s*gzip_comp_level 6;\n\s*gzip_proxied any;\n\s*gzip_types.*?;\n",
        "\n",
        patched,
        flags=re.DOTALL,
    )
    root_marker = "    client_max_body_size 64M;\n"
    if root_marker in patched:
        patched = patched.replace(root_marker, root_marker + gzip_block, 1)

    static_marker = "    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|wasm)$ {"
    app_marker = "    location / {"
    if static_marker in patched:
        patched = patched.replace(static_marker, managed + "\n" + static_marker, 1)
    elif app_marker in patched:
        patched = patched.replace(app_marker, managed + "\n" + app_marker, 1)
    else:
        patched = patched.replace("\n}\n", "\n" + managed + "\n}\n", 1)

    # Prefer /app$uri for any leftover static hits under the old root layout.
    patched = re.sub(
        r"(location\s+~\*\s+\\\.\(js\|css\|png\|jpg\|jpeg\|gif\|ico\|svg\|woff2\?\|ttf\|wasm\)\$\s*\{.*?try_files\s+)\$uri\s+=404;",
        r"\1$uri /app$uri =404;",
        patched,
        count=1,
        flags=re.DOTALL,
    )

    # Old bookmarks like /feed must land in /app/feed (not the root redirector).
    patched = re.sub(
        r"location\s*/\s*\{\s*try_files\s+\$uri\s+\$uri/\s+/index\.html;\s*(?:add_header\s+Cache-Control\s+\"no-cache\";\s*)?\}",
        "location / {\n        return 302 /app$request_uri;\n    }",
        patched,
        count=1,
        flags=re.DOTALL,
    )
    # If already rewritten to 302, keep it; if still try_files to index, force /app.
    if "return 302 /app$request_uri;" not in patched:
        patched = re.sub(
            r"location\s*/\s*\{[^}]*\}",
            "location / {\n        return 302 /app$request_uri;\n    }",
            patched,
            count=1,
            flags=re.DOTALL,
        )
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
echo "Verifying Flutter deferred parts revalidate..."
PART="$(curl -sf https://haneat.app/app/main.dart.js | grep -oE 'main\.dart\.js_1\.part[^"]+\.js' | head -1 || true)"
if [[ -z "${PART}" ]]; then
  echo "FAIL: could not resolve deferred part name from main.dart.js"
  exit 1
fi
part_cc="$(curl -sfI "https://haneat.app/app/${PART}" | tr -d '\r' | grep -i '^cache-control:' || true)"
echo "  ${PART} Cache-Control: ${part_cc:-<missing>}"
if ! echo "$part_cc" | grep -qiE 'no-cache|no-store|must-revalidate'; then
  echo "FAIL: deferred part.js must not be long-cached (stale parts → white screen)"
  exit 1
fi
echo "✓ haneat.app deferred part.js revalidate policy active"
