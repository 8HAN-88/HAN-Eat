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

    location ~* ^/(flutter_service_worker\.js|flutter_bootstrap\.js|version\.json)$ {
        add_header Cache-Control "no-cache";
        try_files $uri =404;
    }

    # Без immutable: иначе браузер годами держит старый main.dart.js после деплоя.
    location = /main.dart.js {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }

    location ^~ /icons/ {
        add_header Cache-Control "no-cache, must-revalidate";
        try_files $uri =404;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|wasm)$ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache";
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
