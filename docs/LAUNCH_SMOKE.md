# Launch smoke tests

Проверка критичных путей перед TestFlight / production.

## Быстрый запуск

```bash
# 1. Backend
cd backend && uvicorn app.main:app --host 127.0.0.1 --port 5001

# 2. Smoke (другой терминал)
./scripts/verify_launch.sh http://127.0.0.1:5001
```

Полный ТЗ-smoke (подписки, creator):

```bash
SMOKE_PASSWORD=yourpass python3 backend/scripts/smoke_tz_full.py
```

## Что проверяет `smoke_launch.py`

| Область | Эндпоинты |
|---------|-----------|
| Public | `/health`, `/system/readiness`, ai-scan limits, prices, channels catalog, `/privacy` |
| Auth | register/login, `POST /auth/refresh` |
| Feed | `GET /feed` |
| Post | `POST /posts` (text) |
| Payments | readiness, history |
| Meal plan | `GET /meal-plans/limits` |
| Subscriptions | `GET /subscriptions/status` (entitlements) |

Exit code `0` — все проверки прошли.

## Flutter unit / integration

```bash
# Unit (кеш ленты, без backend)
flutter test test/feed_api_cache_test.dart

# E2E (нужен backend :5001)
flutter test integration_test/feed_flow_e2e_test.dart \
  --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001

flutter test integration_test/tz_emulator_test.dart \
  --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001
```

## Backend unit tests

```bash
cd backend && python -m pytest tests/ -q
```

## Ручной чеклист (Flutter)

- [ ] Гость: лента и каналы без входа
- [ ] Вход email / Google
- [ ] Лента: при отключении сети — баннер + кеш (если был онлайн-заход)
- [ ] Push в foreground: уведомление в шторке, тап → пост/профиль
- [ ] Создание поста в канале
- [ ] Подписка: checkout → deep link success
- [ ] AI scan: fail-closed без сети; paywall при исчерпании credits
- [ ] AI meal plan: лимиты free / cooldown
- [ ] Release-сборка: нет клиентского Spoonacular / OpenAI
- [ ] `/community` открывает главную ленту (redirect)
