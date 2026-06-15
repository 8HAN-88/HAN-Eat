# Email-вход и безопасность аккаунта

## Что сделано

- Регистрация / вход только по **email + пароль**
- Подтверждение email после регистрации
- Забыли пароль → сброс по ссылке из письма
- В настройках: **Пароль и email** (смена пароля, запрос смены email)

## 1. Деплой backend (консоль Timeweb)

```bash
cd ~/HAN-Eat
git pull origin main
cd backend
source venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
```

Проверка:

```bash
ls migrations/versions/036_email_auth_tokens_v1.py
grep -c verify-email app/api/v1/auth.py
systemctl restart haneat-api
curl -s http://127.0.0.1:8000/health
```

## 2. SMTP в `backend/.env` на сервере

```bash
nano ~/HAN-Eat/backend/.env
```

Пример для Яндекс (нужен **пароль приложения**, не пароль от почты):

```env
REQUIRE_EMAIL_VERIFICATION=true
AUTH_LINK_BASE_URL=haneat://auth
EMAIL_SMTP_HOST=smtp.yandex.ru
EMAIL_SMTP_PORT=587
EMAIL_SMTP_USER=you@yandex.ru
EMAIL_SMTP_PASSWORD=app-password-here
EMAIL_SMTP_USE_TLS=true
EMAIL_FROM=you@yandex.ru
EMAIL_FROM_NAME=HAN Eat
```

```bash
systemctl restart haneat-api
```

## 3. Приложение (Mac)

`HAN-Eat/.env`:

```env
HANEAT_API_BASE=https://api.haneat.app
```

Пересобрать: `flutter run` или Xcode.

## 4. Проверка API

Открой https://api.haneat.app/openapi.json и найди пути:

- `POST /api/v1/auth/verify-email`
- `POST /api/v1/auth/forgot-password`
- `POST /api/v1/auth/reset-password`
- `POST /api/v1/auth/change-password`

## 5. Локально без SMTP

Письма попадают в **лог uvicorn** — скопируй `token` из ссылки `haneat://auth/verify-email?token=...` на экран подтверждения в приложении.

## 6. Письмо не приходит (сброс пароля / подтверждение)

На сервере в консоли Timeweb:

```bash
cd ~/HAN-Eat/backend
source venv/bin/activate
python3 scripts/check_email_config.py
python3 scripts/check_email_config.py --send-test ваш@gmail.com
curl -s http://127.0.0.1:8000/health | python3 -m json.tool
```

В `health` должно быть `"email_smtp_configured": true`. Если `false` — в `backend/.env` не заданы `EMAIL_*` или сервис не перезапущен после правки.

Проверьте в `.env`:

- `EMAIL_SMTP_USER` и `EMAIL_FROM` — **один и тот же** ящик Яндекса
- `EMAIL_SMTP_PASSWORD` — **пароль приложения** (id.yandex.ru → Безопасность → Пароли приложений), не пароль от входа
- после правки: `systemctl restart haneat-api`

Логи ошибок SMTP:

```bash
journalctl -u haneat-api -n 80 --no-pager | grep -iE 'email|smtp|forgot-password'
```

В приложении API всегда отвечает «если аккаунт существует…» — даже если SMTP сломан (безопасность). Проверяйте сервер, а не только почтовый ящик.

## 7. Яндекс SMTP: все варианты `--probe` дают 535

Это отказ **Яндекса** (нет прав на SMTP для ящика с VPS), а не ошибка HAN Eat. Пароль 16 символов и IMAP в настройках — недостаточно, если Яндекс не выдаёт доступ.

**Решение: Resend** (бесплатно ~100 писем/день, работает с Timeweb):

1. Регистрация: https://resend.com → **API Keys** → создать ключ `re_...`
2. В `backend/.env` на сервере:

```env
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_ваш_ключ
EMAIL_FROM=onboarding@resend.dev
EMAIL_FROM_NAME=HAN Eat
AUTH_LINK_BASE_URL=haneat://auth
```

Для production позже: в Resend добавить домен `haneat.app` и сменить `EMAIL_FROM` на `noreply@haneat.app`.

3. `systemctl restart haneat-api`
4. `python3 scripts/check_email_config.py --send-test airat8446@gmail.com`

Яндекс SMTP можно оставить закомментированным — при `EMAIL_PROVIDER=resend` он не используется.

## 8. Отправка на любые адреса (mail.ru, gmail и т.д.)

С `onboarding@resend.dev` Resend разрешает письма **только на email владельца аккаунта** (тест прошёл — это нормально).

Чтобы письма шли **всем пользователям**, верифицируйте домен `haneat.app`:

### 8.1 Resend

1. https://resend.com/domains → **Add Domain** → `haneat.app`
2. Resend покажет DNS-записи (обычно 3 DKIM CNAME + TXT для SPF/DMARC). Скопируйте их.

### 8.2 DNS у регистратора домена

Где управляется DNS для `haneat.app` (Timeweb / Cloudflare / регистратор):

- Добавьте **все** записи из Resend **как указано** (имена вида `resend._domainkey`, `send` и т.п.)
- Не удаляйте существующие MX для почты, если они нужны
- SPF: объедините с существующим TXT или добавьте отдельную запись, как советует Resend

Проверка (через 5–30 мин):

```bash
dig +short CNAME resend._domainkey.haneat.app
```

В Resend статус домена должен стать **Verified**.

### 8.3 Сервер

В `/root/HAN-Eat/backend/.env`:

```env
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_...
EMAIL_FROM=noreply@haneat.app
EMAIL_FROM_NAME=HAN Eat
RESEND_DOMAIN_VERIFIED=true
```

```bash
systemctl restart haneat-api
cd /root/HAN-Eat/backend && source venv/bin/activate
python3 scripts/check_email_config.py --send-test kokmaks2007@mail.ru
```

Или деплой с Mac/GitHub Actions — скрипт `ensure_server_email_env.sh` подхватит `RESEND_DOMAIN_VERIFIED=true`.

### 8.4 Проверка в приложении

1. https://haneat.app → регистрация / «Отправить письмо ещё раз»
2. Проверить inbox и **Спам** (особенно @mail.ru)
