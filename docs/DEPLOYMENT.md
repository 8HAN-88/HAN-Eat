# Деплой HAN Eat (API + приложение)

## Production (Timeweb)

Сервер: `api.haneat.app`, приложение подключается через `HANEAT_API_BASE` / `ServerConfig`.

### 1. Обновление кода

```bash
cd /root/HAN-Eat
git pull
```

### 2. Backend

```bash
cd backend
source venv/bin/activate
pip install -r requirements.txt   # при изменении зависимостей
alembic upgrade head              # обязательно после pull (миграции, напр. 037_post_poll_votes_v1)
```

Проверьте `.env` на сервере (`DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, SMTP для email-auth).

```bash
sudo systemctl restart haneat-api
# или ваш unit: haneat-api.service
```

### 3. Проверка после рестарта

```bash
curl -sS https://api.haneat.app/health
cd /root/HAN-Eat/backend
python3 scripts/smoke_api_check.py --base https://api.haneat.app \
  --login han.test.creator@haneat.dev
```

Ожидаемый результат после выкладки ветки с опросами/ссылками/удалением постов:
`POST /posts/link/preview` → 200, `DELETE /posts/{id}` → 204.

Если smoke показывает **WARN** `404` / `405` на эти эндпоинты — на сервере ещё старый код: повторите шаги 1–2 (`git pull`, `alembic upgrade head`, restart).

Пароль тестовых аккаунтов: [backend/docs/TEST_ACCOUNTS.md](../backend/docs/TEST_ACCOUNTS.md).

### 4. Flutter / мобильное приложение

- Сборка с production API (по умолчанию в `ServerConfig` — `https://api.haneat.app`).
- Локальный backend: `flutter run --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001`

### 5. Откат

```bash
cd /root/HAN-Eat
git checkout <previous-commit>
cd backend && source venv/bin/activate
# откат миграции только если знаете что делаете:
# alembic downgrade -1
sudo systemctl restart haneat-api
```

## Локальная разработка

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # настроить DATABASE_URL, REDIS_URL
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 5001
```

Smoke:

```bash
python3 scripts/smoke_api_check.py --base http://127.0.0.1:5001 \
  --login han.test.creator@haneat.dev
```

## Чеклист после выкладки

См. [SMOKE_CHECKLIST.md](SMOKE_CHECKLIST.md).
