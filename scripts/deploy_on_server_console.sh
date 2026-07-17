#!/usr/bin/env bash
# Деплой backend НА СЕРВЕРЕ (Timeweb → Консоль в браузере).
# Запускать после того как код уже на сервере в /root/HAN-Eat/backend
# (через git pull, загрузку архива или rsync с Mac).
set -euo pipefail

APP_DIR="${APP_DIR:-/root/HAN-Eat}"
export DEBIAN_FRONTEND=noninteractive

echo "== HAN Eat: server-side deploy =="
apt-get update -qq
apt-get install -y -qq ffmpeg

cd "${APP_DIR}/backend"

if [[ -d venv ]]; then
  source venv/bin/activate
else
  python3 -m venv venv
  source venv/bin/activate
fi

ENV="${APP_DIR}/backend/.env"
if grep -q "^MAX_VIDEO_SIZE_MB=" "$ENV" 2>/dev/null; then
  sed -i "s|^MAX_VIDEO_SIZE_MB=.*|MAX_VIDEO_SIZE_MB=0|" "$ENV"
else
  echo "MAX_VIDEO_SIZE_MB=0" >> "$ENV"
fi
# White-screen root cause on web: APP_ENV=development disables haneat.app CORS.
if grep -q "^APP_ENV=" "$ENV" 2>/dev/null; then
  sed -i "s|^APP_ENV=.*|APP_ENV=production|" "$ENV"
else
  echo "APP_ENV=production" >> "$ENV"
fi
if grep -q "^DEBUG=" "$ENV" 2>/dev/null; then
  sed -i "s|^DEBUG=.*|DEBUG=false|" "$ENV"
else
  echo "DEBUG=false" >> "$ENV"
fi
if grep -q "^API_PUBLIC_BASE_URL=" "$ENV" 2>/dev/null; then
  sed -i "s|^API_PUBLIC_BASE_URL=.*|API_PUBLIC_BASE_URL=https://api.haneat.app|" "$ENV"
else
  echo "API_PUBLIC_BASE_URL=https://api.haneat.app" >> "$ENV"
fi
PROD_ORIGINS='https://haneat.app,https://www.haneat.app,https://kitchen.haneat.app,http://localhost:3000,http://localhost:8080'
if grep -q "^ALLOWED_ORIGINS=" "$ENV" 2>/dev/null; then
  sed -i "s|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${PROD_ORIGINS}|" "$ENV"
else
  echo "ALLOWED_ORIGINS=${PROD_ORIGINS}" >> "$ENV"
fi
if [[ -f /etc/nginx/sites-available/haneat-api ]]; then
  sed -i 's/client_max_body_size .*/client_max_body_size 1024M;/' /etc/nginx/sites-available/haneat-api
  nginx -t && systemctl reload nginx
fi

if [[ ! -f /etc/systemd/system/haneat-video-worker.service ]]; then
  cat > /etc/systemd/system/haneat-video-worker.service << EOF
[Unit]
Description=HAN Eat video transcoding worker
After=network.target docker.service haneat-api.service

[Service]
User=root
WorkingDirectory=${APP_DIR}/backend
Environment="PATH=${APP_DIR}/backend/venv/bin:/usr/bin"
ExecStart=${APP_DIR}/backend/venv/bin/python -m app.workers.video_worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
fi

pip install -q -r requirements.txt
bash "${APP_DIR}/scripts/ensure_server_email_env.sh" "${APP_DIR}/backend/.env"
alembic upgrade head
python3 scripts/create_all_test_accounts.py || true
systemctl daemon-reload
systemctl enable haneat-video-worker 2>/dev/null || true
systemctl restart haneat-api
systemctl restart haneat-video-worker 2>/dev/null || true
sleep 2
systemctl is-active haneat-api
systemctl is-active haneat-video-worker 2>/dev/null || echo "video-worker: not running"

echo ""
echo "== health =="
curl -sf http://127.0.0.1:8000/health || curl -sf https://api.haneat.app/health
echo ""

echo ""
echo "== media readiness =="
curl -sf http://127.0.0.1:8000/api/v1/system/readiness | python3 -m json.tool 2>/dev/null | head -40 || true

echo ""
echo "== phone-sync endpoint (ожидаем 401/403, не 404) =="
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  http://127.0.0.1:8000/api/v1/chats/contacts/phone-sync \
  -H 'Content-Type: application/json' -d '{"phone_hashes":[]}' || echo "000")
echo "HTTP ${code}"

echo ""
echo "DONE"
