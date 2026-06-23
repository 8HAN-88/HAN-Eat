#!/usr/bin/env bash
# Обновление backend на Timeweb (api.haneat.app).
# Запуск с Mac:
#   bash scripts/update_production_timeweb.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="${HAN_SSH_KEY:-$HOME/.ssh/haneat_timeweb}"
SSH_USER="${HAN_SSH_USER:-root}"
SSH_HOST="${HAN_SSH_HOST:-89.19.216.60}"
REMOTE_DIR="${HAN_REMOTE_DIR:-/root/HAN-Eat}"

RSYNC_SSH="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new"

echo "== HAN Eat: deploy backend to ${SSH_USER}@${SSH_HOST} =="

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}"
  exit 1
fi

if [[ -f "${ROOT}/backend/firebase-credentials.json" ]]; then
  echo "-- upload Firebase credentials (push) --"
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
    "${SSH_USER}@${SSH_HOST}" "mkdir -p /etc/haneat && chmod 700 /etc/haneat"
  scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
    "${ROOT}/backend/firebase-credentials.json" \
    "${SSH_USER}@${SSH_HOST}:/etc/haneat/firebase-credentials.json"
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
    "${SSH_USER}@${SSH_HOST}" bash -s <<'REMOTE'
set -euo pipefail
ENV="/root/HAN-Eat/backend/.env"
for kv in "FIREBASE_ENABLED=true" "FIREBASE_CREDENTIALS_PATH=/etc/haneat/firebase-credentials.json" "FIREBASE_PROJECT_ID=han-eat"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  if grep -q "^${key}=" "$ENV" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV"
  else
    echo "${key}=${val}" >> "$ENV"
  fi
done
chmod 600 /etc/haneat/firebase-credentials.json
REMOTE
else
  echo "-- skip Firebase credentials (нет backend/firebase-credentials.json) --"
fi

echo "-- sync backend (code + migrations + scripts) --"
rsync -avz --delete \
  -e "${RSYNC_SSH}" \
  --exclude '__pycache__' \
  --exclude '.env' \
  --exclude 'venv' \
  --exclude 'uploads' \
  --exclude 'dev.db' \
  "${ROOT}/backend/" \
  "${SSH_USER}@${SSH_HOST}:${REMOTE_DIR}/backend/"

echo "-- remote: pip, migrations, restart --"
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
  "${SSH_USER}@${SSH_HOST}" bash -s <<'REMOTE'
set -euo pipefail
APP_DIR="/root/HAN-Eat"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ffmpeg
cd "$APP_DIR/backend"
if [[ -d venv ]]; then
  source venv/bin/activate
else
  python3 -m venv venv
  source venv/bin/activate
fi
pip install -q -r requirements.txt
ENV="$APP_DIR/backend/.env"
if grep -q "^MAX_VIDEO_SIZE_MB=" "$ENV" 2>/dev/null; then
  sed -i "s|^MAX_VIDEO_SIZE_MB=.*|MAX_VIDEO_SIZE_MB=0|" "$ENV"
else
  echo "MAX_VIDEO_SIZE_MB=0" >> "$ENV"
fi
if [[ -f /etc/nginx/sites-available/haneat-api ]]; then
  sed -i 's/client_max_body_size .*/client_max_body_size 1024M;/' /etc/nginx/sites-available/haneat-api
  if [[ -f "$APP_DIR/scripts/patch_nginx_realtime_sse.sh" ]]; then
    bash "$APP_DIR/scripts/patch_nginx_realtime_sse.sh" || true
  fi
  nginx -t && systemctl reload nginx
fi
if [[ ! -f /etc/systemd/system/haneat-video-worker.service ]]; then
  cat > /etc/systemd/system/haneat-video-worker.service << EOF
[Unit]
Description=HAN Eat video transcoding worker
After=network.target docker.service haneat-api.service
Requires=docker.service

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
alembic upgrade head
python3 scripts/create_all_test_accounts.py || true
systemctl daemon-reload
systemctl enable haneat-video-worker 2>/dev/null || true
systemctl restart haneat-api
systemctl restart haneat-video-worker 2>/dev/null || true
sleep 2
systemctl is-active haneat-api
systemctl is-active haneat-video-worker 2>/dev/null || echo "video-worker: not running yet"
REMOTE

echo "-- verify API --"
"${ROOT}/scripts/verify_launch.sh" "https://api.haneat.app" || true

echo "Done. Flutter: HANEAT_API_BASE=https://api.haneat.app (см. .env)"
