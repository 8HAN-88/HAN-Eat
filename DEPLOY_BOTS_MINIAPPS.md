# 🚀 Deployment Checklist — Боты и Мини-приложения (MVP)

## 1. GitHub PR (сделай один раз)

```bash
# В терминале на своей машине (где есть gh auth)
gh pr create \
  --title "feat(bots-miniapps): Полный MVP Ботов и Мини-приложений (как в Telegram)" \
  --body-file docs/BOTS_MINIAPPS_TESTING_GUIDE.md \
  --base main \
  --head feat/bots-miniapps-mvp
```

Или просто открой ссылку:
https://github.com/8HAN-88/HAN-Eat/pull/new/feat/bots-miniapps-mvp

## 2. Backend — Production (Timeweb / твой сервер)

### 2.1. Применить миграцию БД (ОБЯЗАТЕЛЬНО!)

```bash
# На сервере
cd /opt/haneat/backend
psql "$DATABASE_URL" -f migrations/add_bot_support.sql
```

Или через Alembic (если используешь):
```bash
alembic upgrade head
```

### 2.2. Перезапустить backend

```bash
# systemd
sudo systemctl restart haneat-backend

# или docker
docker-compose restart backend

# или gunicorn / uvicorn
pkill -f "uvicorn app.main" && nohup uvicorn app.main:app --host 0.0.0.0 --port 8000 &
```

### 2.3. Проверить логи

```bash
journalctl -u haneat-backend -n 50 --no-pager
# или
docker logs -f backend
```

Убедись, что нет ошибок импорта `bot_handler`, `bots`, `bot_chats`.

## 3. Web (HanWe)

### 3.1. Автоматический деплой (рекомендуется)

Сделай merge PR → GitHub Actions автоматически:
- Соберёт `web-social`
- Зальёт на `/var/www/haneat-web/`

### 3.2. Ручной деплой (если нужно срочно)

На сервере:

```bash
cd /opt/haneat
git pull origin main

cd frontend   # или где у тебя Flutter
flutter clean
flutter pub get
flutter build web --release \
  --dart-define=APP_VARIANT=social \
  --dart-define=API_BASE=https://api.haneat.app

sudo rsync -av --delete build/web/ /var/www/haneat-web/
sudo nginx -t && sudo systemctl reload nginx
```

## 4. Тестирование (после деплоя)

Открой HanWe и пройди по `docs/BOTS_MINIAPPS_TESTING_GUIDE.md`:

1. Создать бота
2. Добавить команды
3. Добавить бота в чат
4. Проверить `/start` / `/help`
5. Проверить Inline Mode (`@bot query`)
6. Проверить мини-приложения через каталог и Attach Menu

## 5. Rollback (на случай проблем)

### Backend
```bash
# Откат миграции (если нужно)
psql "$DATABASE_URL" -c "DROP TABLE IF EXISTS bot_commands;"
psql "$DATABASE_URL" -c "ALTER TABLE users DROP COLUMN IF EXISTS is_bot, DROP COLUMN IF EXISTS bot_token, ...;"
```

### Web
```bash
# Откат web
sudo rsync -av --delete /var/www/haneat-web-backup/ /var/www/haneat-web/
```

---

**Готово.** После выполнения пунктов 2 и 3 фича будет доступна пользователям HanWe.