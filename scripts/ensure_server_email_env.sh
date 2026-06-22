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
  # Убираем все дубликаты ключа — иначе pydantic/dotenv может взять старое значение.
  grep -v "^${key}=" "$ENV" > "${ENV}.tmp" || true
  mv "${ENV}.tmp" "$ENV"
  echo "${key}=${val}" >> "$ENV"
}

# Resend: ключ уже в .env; включаем провайдер явно.
set_kv EMAIL_PROVIDER resend

# Resend: по умолчанию noreply@haneat.app (домен верифицирован).
# Тестовый режим только при явном RESEND_DOMAIN_VERIFIED=false.
if grep -q '^RESEND_DOMAIN_VERIFIED=false' "$ENV" 2>/dev/null; then
  set_kv EMAIL_FROM onboarding@resend.dev
else
  set_kv EMAIL_FROM noreply@haneat.app
  set_kv RESEND_DOMAIN_VERIFIED true
fi

grep -q '^EMAIL_FROM_NAME=' "$ENV" 2>/dev/null || set_kv EMAIL_FROM_NAME "HAN Eat"

echo "ensure_server_email_env: EMAIL_PROVIDER=$(grep '^EMAIL_PROVIDER=' "$ENV" | tail -1 | cut -d= -f2-)"
echo "ensure_server_email_env: EMAIL_FROM=$(grep '^EMAIL_FROM=' "$ENV" | tail -1 | cut -d= -f2-)"
echo "ensure_server_email_env: RESEND_API_KEY set=$(grep -c '^RESEND_API_KEY=.' "$ENV" || true)"
