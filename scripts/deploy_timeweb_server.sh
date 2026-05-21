#!/usr/bin/env bash
# Bootstrap HAN Eat API on Timeweb (Ubuntu 24.04, Amsterdam).
# Run as root on the server (web console or SSH):
#   bash deploy_timeweb_server.sh
set -euo pipefail

HAN_SSH_PUBKEY="${HAN_SSH_PUBKEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIR7s+y4H6czF/oOBpOW5bvd1LgCtPqoNEDBk/lloASU haneat-timeweb}"
REPO_URL="${REPO_URL:-https://github.com/8HAN-88/HAN-Eat.git}"
APP_DIR="${APP_DIR:-/root/HAN-Eat}"
API_DOMAIN="${API_DOMAIN:-api.haneat.app}"

echo "== HAN Eat Timeweb deploy =="

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "-- 1/8 SSH key --"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if ! grep -qF "${HAN_SSH_PUBKEY}" /root/.ssh/authorized_keys 2>/dev/null; then
  echo "${HAN_SSH_PUBKEY}" >> /root/.ssh/authorized_keys
fi
systemctl restart ssh || systemctl restart sshd || true

echo "-- 2/8 system packages --"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
timedatectl set-timezone Europe/Amsterdam
apt-get install -y -qq git curl wget nano ufw fail2ban \
  python3 python3-pip python3-venv nginx certbot python3-certbot-nginx

echo "-- 3/8 firewall --"
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

echo "-- 4/8 docker --"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

echo "-- 5/8 postgres + redis --"
mkdir -p /root/haneat
CREDS="/root/haneat/.db_credentials"
if [[ -f "$CREDS" ]]; then
  # shellcheck disable=SC1090
  source "$CREDS"
else
  DB_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  echo "DB_PASS=${DB_PASS}" > "$CREDS"
  chmod 600 "$CREDS"
fi

cat > /root/haneat/docker-compose.yml << EOF
services:
  postgres:
    image: postgres:15
    container_name: haneat-postgres
    environment:
      POSTGRES_USER: haneat
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: haneat
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
    ports:
      - "127.0.0.1:5432:5432"

  redis:
    image: redis:7-alpine
    container_name: haneat-redis
    restart: unless-stopped
    ports:
      - "127.0.0.1:6379:6379"

volumes:
  postgres_data:
EOF

cd /root/haneat
docker compose up -d

echo "-- 6/8 application code --"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" pull --ff-only || true
else
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR/backend"
python3 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt

SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')"
ENV_FILE="$APP_DIR/backend/.env"

upsert_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" << ENVEOF
APP_ENV=production
DEBUG=false
SECRET_KEY=${SECRET_KEY}
DATABASE_URL=postgresql://haneat:${DB_PASS}@127.0.0.1:5432/haneat
REDIS_URL=redis://127.0.0.1:6379/0
REDIS_ENABLED=true
RATE_LIMIT_ENABLED=true
RATE_LIMIT_PER_MINUTE=120
API_PUBLIC_BASE_URL=https://${API_DOMAIN}
ALLOWED_ORIGINS=["https://haneat.app","https://www.haneat.app"]
FRONTEND_URL=https://haneat.app
GOOGLE_OAUTH_CLIENT_IDS=
SPOONACULAR_API_KEY=
OPENAI_API_KEY=
YOOKASSA_ENABLED=false
YOOKASSA_SHOP_ID=
YOOKASSA_SECRET_KEY=
S3_ACCESS_KEY=
S3_SECRET_KEY=
CDN_URL=https://cdn.haneat.app
FIREBASE_ENABLED=false
FIREBASE_CREDENTIALS_PATH=
FIREBASE_PROJECT_ID=
STRIPE_ENABLED=false
ENVEOF
fi

upsert_env "APP_ENV" "production"
upsert_env "DEBUG" "false"
upsert_env "SECRET_KEY" "$SECRET_KEY"
upsert_env "DATABASE_URL" "postgresql://haneat:${DB_PASS}@127.0.0.1:5432/haneat"
upsert_env "REDIS_URL" "redis://127.0.0.1:6379/0"
upsert_env "REDIS_ENABLED" "true"
upsert_env "RATE_LIMIT_ENABLED" "true"
upsert_env "RATE_LIMIT_PER_MINUTE" "120"
upsert_env "API_PUBLIC_BASE_URL" "https://${API_DOMAIN}"
upsert_env "ALLOWED_ORIGINS" "https://haneat.app,https://www.haneat.app"
upsert_env "FRONTEND_URL" "https://haneat.app"

alembic upgrade head

echo "-- 7/8 systemd --"
cat > /etc/systemd/system/haneat-api.service << EOF
[Unit]
Description=HAN Eat FastAPI
After=network.target docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=${APP_DIR}/backend
Environment="PATH=${APP_DIR}/backend/venv/bin"
ExecStart=${APP_DIR}/backend/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable haneat-api
systemctl restart haneat-api

echo "-- 8/8 nginx --"
cat > /etc/nginx/sites-available/haneat-api << EOF
server {
    listen 80;
    server_name ${API_DOMAIN};

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/haneat-api /etc/nginx/sites-enabled/haneat-api
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

cat > /root/haneat/SECRETS_TODO.txt << EOF
Fill these in: nano ${ENV_FILE}
Then: systemctl restart haneat-api

Required for full production:
  GOOGLE_OAUTH_CLIENT_IDS=
  SPOONACULAR_API_KEY=
  OPENAI_API_KEY=
  YOOKASSA_SHOP_ID=
  YOOKASSA_SECRET_KEY=
  S3_ACCESS_KEY=
  S3_SECRET_KEY=
  CDN_URL=
  FIREBASE_CREDENTIALS_PATH=/etc/haneat/firebase-credentials.json
  FIREBASE_PROJECT_ID=

DB password saved in: ${CREDS}
EOF

echo ""
echo "== DONE =="
echo "Local health:  curl -s http://127.0.0.1:8000/health"
echo "DB creds:      cat ${CREDS}"
echo "Secrets todo:  cat /root/haneat/SECRETS_TODO.txt"
echo ""
echo "Next (after DNS api -> this server, grey cloud):"
echo "  certbot --nginx -d ${API_DOMAIN}"
echo ""
echo "Try SSH from Mac:"
echo "  ssh -i ~/.ssh/haneat_timeweb root@$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

curl -sf http://127.0.0.1:8000/health && echo "" || echo "WARN: health check failed — check journalctl -u haneat-api"
