#!/usr/bin/env bash
# Включить push на production API (Timeweb).
#
# 1. Скачайте JSON: Firebase Console → Project han-eat → Settings → Service accounts
#    → Generate new private key
# 2. Запуск:
#    bash scripts/enable_firebase_push_prod.sh ~/Downloads/han-eat-firebase-adminsdk.json
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CREDS_SRC="${1:-}"
SSH_KEY="${HAN_SSH_KEY:-$HOME/.ssh/haneat_timeweb}"
SSH_USER="${HAN_SSH_USER:-root}"
SSH_HOST="${HAN_SSH_HOST:-89.19.216.60}"
REMOTE_ENV="/root/HAN-Eat/backend/.env"
REMOTE_CREDS="/etc/haneat/firebase-credentials.json"
PROJECT_ID="${FIREBASE_PROJECT_ID:-han-eat}"

if [[ -z "${CREDS_SRC}" || ! -f "${CREDS_SRC}" ]]; then
  echo "Usage: $0 /path/to/firebase-adminsdk-*.json"
  echo ""
  echo "Скачайте ключ: https://console.firebase.google.com/project/han-eat/settings/serviceaccounts/adminsdk"
  exit 1
fi

if ! python3 -c "import json; d=json.load(open('${CREDS_SRC}')); assert d.get('type')=='service_account'; assert d.get('project_id')"; then
  echo "Файл не похож на Firebase service account JSON"
  exit 1
fi

echo "== Copy credentials to Mac backend/ (local dev) =="
cp "${CREDS_SRC}" "${ROOT}/backend/firebase-credentials.json"
chmod 600 "${ROOT}/backend/firebase-credentials.json"

echo "== Enable FIREBASE in local backend/.env =="
LOCAL_ENV="${ROOT}/backend/.env"
touch "${LOCAL_ENV}"
upsert() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "${LOCAL_ENV}" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "${LOCAL_ENV}"
  else
    echo "${key}=${val}" >> "${LOCAL_ENV}"
  fi
}
upsert FIREBASE_ENABLED true
upsert FIREBASE_CREDENTIALS_PATH "./firebase-credentials.json"
upsert FIREBASE_PROJECT_ID "${PROJECT_ID}"

cd "${ROOT}/backend"
python3 scripts/check_firebase_config.py

echo ""
echo "== Deploy credentials + env to ${SSH_USER}@${SSH_HOST} =="
deploy_prod() {
  ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    "${SSH_USER}@${SSH_HOST}" "mkdir -p /etc/haneat && chmod 700 /etc/haneat"
  scp -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new \
    "${CREDS_SRC}" "${SSH_USER}@${SSH_HOST}:${REMOTE_CREDS}"
  ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new "${SSH_USER}@${SSH_HOST}" bash -s <<REMOTE
set -euo pipefail
ENV="${REMOTE_ENV}"
chmod 600 ${REMOTE_CREDS}
for kv in \
  "FIREBASE_ENABLED=true" \
  "FIREBASE_CREDENTIALS_PATH=${REMOTE_CREDS}" \
  "FIREBASE_PROJECT_ID=${PROJECT_ID}"; do
  key="\${kv%%=*}"
  val="\${kv#*=}"
  if grep -q "^\${key}=" "\$ENV" 2>/dev/null; then
    sed -i "s|^\${key}=.*|\${key}=\${val}|" "\$ENV"
  else
    echo "\${key}=\${val}" >> "\$ENV"
  fi
done
systemctl restart haneat-api
sleep 2
systemctl is-active haneat-api
REMOTE
}

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}"
else
  if deploy_prod; then
    echo "  OK prod deploy via SSH"
  else
    echo ""
    echo "SSH не удался (Connection closed / timeout)."
    echo "Локально push уже работает. Prod — через панель Timeweb:"
    echo ""
    echo "  1) Панель Timeweb → ваш VPS → Консоль / VNC в браузере"
    echo "  2) Загрузите JSON на сервер:"
    echo "       ${REMOTE_CREDS}"
    echo "     (SFTP/файловый менеджер или с Mac когда SSH заработает:)"
    echo "       scp -i ${SSH_KEY} \\"
    echo "         ${CREDS_SRC} ${SSH_USER}@${SSH_HOST}:${REMOTE_CREDS}"
    echo "  3) В ${REMOTE_ENV} добавьте/обновите:"
    echo "       FIREBASE_ENABLED=true"
    echo "       FIREBASE_CREDENTIALS_PATH=${REMOTE_CREDS}"
    echo "       FIREBASE_PROJECT_ID=${PROJECT_ID}"
    echo "  4) systemctl restart haneat-api"
    echo ""
    echo "  Если SSH с Mac не пускает: Timeweb → Сеть → проверьте firewall,"
    echo "  добавьте ваш SSH-ключ в authorized_keys через веб-консоль."
    echo "  Подробнее: docs/FIREBASE_PUSH_ENABLE.md#ssh-connection-closed"
  fi
fi

echo ""
echo "== Verify prod readiness =="
if curl -sf "https://api.haneat.app/api/v1/system/readiness" | python3 -c "
import json,sys
d=json.load(sys.stdin)
fb=d.get('infrastructure',{}).get('firebase',{})
print('firebase.enabled:', fb.get('enabled'))
print('firebase.push_ready:', fb.get('push_ready'))
issues=fb.get('issues') or d.get('issues')
if issues:
    print('issues:', issues)
sys.exit(0 if fb.get('push_ready') else 1)
"; then
  :
else
  echo "  Prod: push ещё не включён (нужен шаг с сервером выше)."
fi

echo ""
echo "Done. iOS: загрузите APNs key в Firebase → Cloud Messaging → Apple app configuration."
