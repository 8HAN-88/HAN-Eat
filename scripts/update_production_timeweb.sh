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
cd /root/HAN-Eat/backend
if [[ -d venv ]]; then
  source venv/bin/activate
else
  python3 -m venv venv
  source venv/bin/activate
fi
pip install -q -r requirements.txt
alembic upgrade head
python3 scripts/create_all_test_accounts.py || true
systemctl restart haneat-api
sleep 2
systemctl is-active haneat-api
REMOTE

echo "-- verify API --"
"${ROOT}/scripts/verify_launch.sh" "https://api.haneat.app" || true

echo "Done. Flutter: HANEAT_API_BASE=https://api.haneat.app (см. .env)"
