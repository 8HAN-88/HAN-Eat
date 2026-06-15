#!/usr/bin/env bash
# Вызывается на сервере после деплоя: Resend вместо SMTP, корректный FROM.
set -euo pipefail

ENV="${1:-/root/HAN-Eat/backend/.env}"

if [[ ! -f "$ENV" ]]; then
  echo "ensure_server_email_env: missing $ENV"
  exit 1
fi

set_kv() {
  local key="$1"
  local val="$2"
  if grep -q "^${key}=" "$ENV" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV"
  else
    echo "${key}=${val}" >> "$ENV"
  fi
}

# Resend: ключ уже в .env; включаем провайдер явно.
set_kv EMAIL_PROVIDER resend

# После верификации домена haneat.app в Resend — в .env на сервере:
#   RESEND_DOMAIN_VERIFIED=true
#   EMAIL_FROM=noreply@haneat.app
if grep -q '^RESEND_DOMAIN_VERIFIED=true' "$ENV" 2>/dev/null; then
  set_kv EMAIL_FROM noreply@haneat.app
elif grep -q '^EMAIL_FROM=noreply@haneat.app' "$ENV" 2>/dev/null; then
  :
elif grep -q '^EMAIL_FROM=.*@haneat.app' "$ENV" 2>/dev/null; then
  :
else
  set_kv EMAIL_FROM onboarding@resend.dev
fi

grep -q '^EMAIL_FROM_NAME=' "$ENV" 2>/dev/null || set_kv EMAIL_FROM_NAME "HAN Eat"

echo "ensure_server_email_env: EMAIL_PROVIDER=$(grep '^EMAIL_PROVIDER=' "$ENV" | cut -d= -f2-)"
echo "ensure_server_email_env: EMAIL_FROM=$(grep '^EMAIL_FROM=' "$ENV" | cut -d= -f2-)"
echo "ensure_server_email_env: RESEND_API_KEY set=$(grep -c '^RESEND_API_KEY=.' "$ENV" || true)"
