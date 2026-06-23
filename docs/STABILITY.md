# Стабильность клиента HAN Eat (v1)

## Автоматический прогон (локально)

```bash
./scripts/release_all_checks.sh
# С проверкой production API:
RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh
```

Чеклист после правок старта, локальных сервисов и сети.

## Сборка и запуск

| Действие | Команда |
|----------|---------|
| iPhone (debug) | `./scripts/run_ios_physical.sh [DEVICE_ID]` — OAuth и API из `.env` через `load_dart_defines.sh` |
| Release IPA | `./scripts/build_ios_release.sh [https://api.haneat.app]` |
| Release AAB | `./scripts/build_android_release.sh [https://api.haneat.app]` |
| Проверка клиента | `./scripts/check_client_stability.sh` |
| Pre-release | `./scripts/pre_release_check.sh` |
| Smoke backend | `./scripts/smoke_launch.sh https://api.haneat.app` |

После смены bundle / Firebase: удалить приложение с устройства, доверить разработчика (Настройки → VPN и управление устройством).

### Долго «Running pod install…»

Причина: CocoaPods CDN + отсутствовал `ios/Pods/Manifest.lock` (установка обрывалась).

```bash
./scripts/ios_ensure_pods.sh   # ~15–30 с вместо 10–30 мин
./scripts/run_ios_physical.sh
```

Если `flutter run` завис на **Installing and launching** / Dart VM Service:

1. Разблокируйте iPhone, кабель USB.
2. Mac: **Конфиденциальность → Автоматизация** — разрешите Cursor/Terminal управлять Xcode.
3. iPhone: **Настройки → Конфиденциальность → Локальная сеть** — «Разрешить» для Python (если спрашивало).
4. Установка без отладчика: `./scripts/run_ios_install_only.sh` → откройте приложение на телефоне вручную.

### Белый экран и мгновенный вылет (iOS 26)

**Частая причина — iOS не доверяет подписи разработчика** (в логах: `invalid code signature` / `profile has not been explicitly trusted`):

1. **Удалите** HAN Eat с iPhone (долгое нажатие → удалить).
2. **Настройки → Основные → VPN и управление устройством** → **Доверять** профилю «Apple Development: …».
3. **Настройки → Конфиденциальность и безопасность → Режим разработчика** → **ВКЛ** (перезагрузка iPhone).
4. Установите заново: `./scripts/run_ios_install_only.sh` → откройте приложение **вручную** на телефоне.
5. Если после доверия всё ещё вылетает — `./scripts/run_ios_physical.sh` и смотрите `flutter logs -d DEVICE_ID` при запуске.

Другие исправления в коде: двойная регистрация плагинов в `AppDelegate` (только `didInitializeImplicitFlutterEngine`); восстановление повреждённых Hive-файлов при старте на iOS.

## Что защищено в коде

- **Ранний UI**: `StartupShell` → `HanEatApp` без блокировки Firebase/Hive.
- **Сервисы**: `ensureInitialized()` + `ServicesReadyGate` для shopping, favorites, meal plan, categories.
- **Избранное**: `safeIsFavorite` / `safeToggleFavorite` в ленте и каналах.
- **Рилсы**: загрузка и видео только при активной вкладке «Рилсы»; prefetch соседей с задержкой.
- **Шрифт**: Manrope в `assets/fonts/` (без сети при старте).
- **Вход**: retry + 60s timeout; подсказка «Подключаемся к серверу…» (вход, регистрация, сброс пароля).
- **API warm-up**: `GET /system/readiness` в фоне после bootstrap.
- **Backend login**: начисление AI scan credits в фоне (ответ login быстрее).
- **Уведомления**: расписание через UTC (корректно для любого offset).

## Realtime и офлайн-кэши (2026)

### SSE `/api/v1/realtime/stream`

Единый канал событий для авторизованного пользователя (Redis + in-memory fallback на backend).

| Событие | Действие клиента |
|---------|------------------|
| `notification.new` | обновить бейдж и список уведомлений |
| `unread_counts` | синхронизировать счётчики |
| `chat.inbox` | обновить список чатов / бейджи |
| `sync` | фоновое обновление ленты, рилсов, чатов |

Клиент: `UserRealtimeService` — reconnect, пауза в фоне / скрытой вкладке Web.  
Fallback polling: **90 с** без SSE, **180 с** с активным SSE (уведомления, чаты).

Nginx: для SSE нужен `proxy_buffering off` на `/api/v1/realtime/stream` (`scripts/patch_nginx_realtime_sse.sh`, деплой backend).

### Кэши (stale-while-revalidate)

Паттерн: `peek` / `warmUp` при старте → мгновенный UI → фоновый refresh с API.

| Сервис | Что кэширует |
|--------|----------------|
| `FeedApiCache` | варианты ленты: `rec_*`, `following_*`, `rec_reels*` |
| `FeedCacheService` | legacy-синк ленты + зеркало в `rec_all_personalized` |
| `ChatCacheService` | inbox чатов |
| `NotificationCacheService` | список уведомлений |
| `ProfileCacheService` / `UserPostsCacheService` | профиль и стена |
| `MenuRecommendationsCache` / `MenuSearchCache` | меню |
| `GlobalSearchCache` | глобальный поиск |
| `SubscriptionStatusCache` | статус подписки |

`FeedCacheService` и `FeedApiCache` связаны: запись/удаление/патч поста дублируется в оба слоя; поиск поста по id смотрит оба.

Прогрев в `bootstrap.dart`: `FeedApiCache.warmUp()`, чаты, профиль, меню, поиск, подписка.

### Production smoke

```bash
RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh
# или только stability:
./scripts/verify_stability_prod.sh
```

Проверяет: health, realtime 401/403, privacy guards, `version.json`, `smoke_launch.py`.

## Ручной smoke на iPhone

1. Холодный старт → главная без белого экрана > 3 с.
2. Сразу после входа: Список покупок, Избранное, План питания — без вылета.
3. Лента → рецепт из поста → избранное (сердечко).
4. Главная → вкладка «Рилсы» только после переключения (нет лишней загрузки на «Рекомендации»).
5. Вход при Wi‑Fi / LTE; при таймауте — повтор через 30 с.
6. Выход / вход другим аккаунтом — без зависания.

### Realtime и кэши (после деплоя)

1. DevTools / Charles: `GET /api/v1/realtime/stream` — **200 pending** при входе.
2. Баннер «нет связи» появляется и исчезает при восстановлении.
3. Лента, чаты, профиль, уведомления — открываются из кэша, затем обновляются.
4. Рилсы: первый сразу; свайп вперёд/назад без долгой паузы.
5. Меню: рекомендации + повторный поиск из кэша.
6. Глобальный поиск (лупа): повторный запрос мгновенный.
7. Фоновая вкладка Web → SSE пауза; возврат → reconnect + `sync`.

## Сервер

Если smoke печатает `WARN POST /auth/login took …s (>8s)`:

```bash
sudo systemctl status haneat-api
sudo journalctl -u haneat-api -n 100 --no-pager
```

Типичные причины: cold start, медленный PostgreSQL, Redis, перегруз Timeweb.

## Release

- `APP_ENV=production` в IPA (`build_ios_release.sh`).
- Google: `GOOGLE_WEB_CLIENT_ID` и `GOOGLE_IOS_CLIENT_ID` в `.env` → попадают в `--dart-define`.
- Не вшивать `OPENAI_API_KEY` в store-билд (только backend).

См. также [RELEASE_V1_NO_PAYMENT.md](RELEASE_V1_NO_PAYMENT.md).

## Статус автоматизации (локально)

| Проверка | Команда | Ожидание |
|----------|---------|----------|
| Клиент | `./scripts/check_client_stability.sh` | exit 0 |
| Pre-release | `./scripts/pre_release_check.sh` | exit 0 |
| TestFlight prep | `./scripts/pre_testflight_check.sh` | без FAIL |
| Prod API + stability | `RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh` | smoke + stability |
| Stability only | `./scripts/verify_stability_prod.sh` | realtime, privacy, version.json |
| Backend unit | `cd backend && python3 -m pytest tests/ -q` | 61 passed |

После деплоя backend с ускоренным login — перезапустите `haneat-api` на сервере.
