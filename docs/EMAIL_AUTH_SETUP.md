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
