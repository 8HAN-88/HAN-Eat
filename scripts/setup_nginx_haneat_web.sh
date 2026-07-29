#!/usr/bin/env bash
# Одноразовая настройка nginx для haneat.app (PWA) на Timeweb.
# Запуск на сервере (консоль Timeweb или SSH):
#   bash scripts/setup_nginx_haneat_web.sh
set -euo pipefail

WEB_ROOT="${HAN_WEB_ROOT:-/var/www/haneat-web}"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "== HAN Eat: nginx для haneat.app =="

mkdir -p "$WEB_ROOT/.well-known"
chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || true

if [[ -f "$TEMPLATE_DIR/web/.well-known/assetlinks.json" ]]; then
  cp "$TEMPLATE_DIR/web/.well-known/assetlinks.json" "$WEB_ROOT/.well-known/"
  echo "  OK assetlinks.json скопирован в $WEB_ROOT/.well-known/"
else
  echo "  WARN нет web/.well-known/assetlinks.json — сгенерируйте: ./scripts/generate_assetlinks.sh"
fi

cat > /etc/nginx/sites-available/haneat-web << 'EOF'
server {
    listen 80;
    server_name haneat.app www.haneat.app;

    root /var/www/haneat-web;
    index index.html;

    client_max_body_size 64M;
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

    location = /.well-known/assetlinks.json {
        default_type application/json;
        add_header Cache-Control "public, max-age=3600";
        try_files $uri =404;
    }

    location = /privacy {
        proxy_pass https://api.haneat.app/privacy;
        proxy_set_header Host api.haneat.app;
    }
    location = /terms {
        proxy_pass https://api.haneat.app/terms;
        proxy_set_header Host api.haneat.app;
    }

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

    location ~* ^/(flutter_service_worker\.js|flutter_bootstrap\.js|version\.json|manifest\.json|flutter\.js)$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # Deferred parts: unversioned filenames — always revalidate.
    location ~* ^/main\.dart\.js_.+\.part\.js$ {
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
        try_files $uri =404;
    }

    # Entrypoint only (not *.part.js). Prefer regex over ^~ so parts aren't swallowed.
    location ~* ^/main\.dart\.js$ {
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

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|wasm)$ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }
}
EOF

ln -sf /etc/nginx/sites-available/haneat-web /etc/nginx/sites-enabled/haneat-web
nginx -t
systemctl reload nginx

echo ""
echo "✓ nginx haneat-web активен"
echo "  Деплой статики: ./scripts/deploy_web_timeweb.sh (с Mac)"
echo "  SSL: certbot --nginx -d haneat.app -d www.haneat.app"
echo "  Проверка: curl -sI https://haneat.app/ | head -5"
