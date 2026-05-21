# Чеклист перед публичным релизом HAN Eat

## Спринт 1 — инфраструктура

- [x] Bundle ID `com.haneat.app` (Android/iOS) — обновить приложения в Firebase Console
- [x] Android release signing через `android/key.properties` (см. `key.properties.example`)
- [x] Гостевой просмотр ленты/каналов без входа
- [x] Избранное из `RecipeService`, не mock
- [x] Юридические ссылки в настройках (`LegalUrls`)
- [x] AI scan только через API в release (не клиентский OpenAI)
- [x] `.env` убран из assets
- [x] Swagger только в `APP_ENV=development`
- [x] `alembic upgrade head` (миграция 033 meal plan cooldown) — `cd backend && alembic upgrade head`
- [x] HTML privacy/terms в `static/legal/` + API `/privacy`, `/terms`
- [ ] Опубликовать на https://haneat.app (см. `docs/LEGAL_PAGES_DEPLOY.md`)

## Спринт 2 — prod API, медиа, оплата (код)

- [x] `AppBuildConfig` + `scripts/build_*_release.sh` с `HANEAT_API_BASE`
- [x] `GET /api/v1/system/readiness` — платежи + S3 + production guards
- [x] Deep link оплаты: `haneat://subscription/success|cancel`
- [x] `RecipeApiService` — только backend в release (без клиентского Spoonacular)
- [x] Документация: `docs/YOOKASSA_WEBHOOK.md`, `docs/SUBSCRIPTION_STORE_STRATEGY.md`
- [x] `GoogleService-Info.plist.example`, `scripts/android_print_sha1.sh`
- [ ] Production API на сервере: `API_PUBLIC_BASE_URL`, `APP_ENV=production`
- [ ] S3: `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `CDN_URL`
- [ ] ЮKassa webhook в ЛК на публичный URL
- [x] Google Sign-In: `python3 scripts/verify_google_signin.py` → 0 exit
- [ ] Решение App Store IAP vs web-only (см. `SUBSCRIPTION_STORE_STRATEGY.md`)

## Спринт 3 — качество (код)

- [x] Smoke: `scripts/verify_launch.sh` + `docs/LAUNCH_SMOKE.md`
- [x] Legacy Firestore отключён в release (`LegacyFirestoreConfig`)
- [x] Firebase Crashlytics (`lib/core/crash_reporting.dart`)
- [x] UX: ошибки ленты ≠ пусто, офлайн-кеш feed, global offline banner
- [x] Push foreground → локальные уведомления + единый FCM payload
- [x] Ad-free: promoted скрыты для платных тарифов (backend + entitlements)
- [x] Auth: banned/deleted на login, Google, refresh token
- [x] Backend: Redis lock для maintenance, пагинация expiry подписок
- [x] Backend: global rate limit (Redis, `RATE_LIMIT_ENABLED`)
- [x] Unit: `test/feed_api_cache_test.dart`, `backend/tests/test_push_service.py`
- [x] E2E: `integration_test/feed_flow_e2e_test.dart`, `integration_test/tz_emulator_test.dart`
- [x] CI: `launch-verify.yml` — pytest + smoke + subscriptions/refresh
- [ ] TestFlight / Internal testing — `pre_testflight_check` OK; **архив** `build/ios/archive/Runner.xcarchive` собран; нужен **iOS Distribution** для IPA (см. `docs/TESTFLIGHT.md`)
- [x] Crashlytics: Upload Symbols в Xcode Build Phases
- [ ] Прогнать smoke на staging/production API
- [x] Локально: `./scripts/verify_launch.sh http://127.0.0.1:5001`

## Спринт 4 — релиз и сторы (документация + скрипты)

- [x] `docs/TESTFLIGHT.md` — загрузка в App Store Connect
- [x] `docs/GOOGLE_SIGNIN_SETUP.md` — Firebase + SHA-1 + env
- [x] `backend/.env.production.example`
- [x] `scripts/verify_launch.sh` — health + readiness + smoke
- [x] `scripts/build_staging_*.sh` — staging API
- [x] FAB «Загрузить» → `CommunityUploadScreen` (не дубль таба)

## Спринт 5 — юридическое и данные

- [x] Privacy / Terms HTML + эндпоинты `/privacy`, `/terms`
- [x] Избранное API per-user (`favorites:{user_id}`) + auth в клиенте
- [x] `ITSAppUsesNonExemptEncryption` для TestFlight
- [x] CI: `.github/workflows/launch-verify.yml`
- [ ] Деплой legal на haneat.app

## Команды

```bash
# Backend
cd backend && alembic upgrade head
APP_ENV=production uvicorn app.main:app --host 0.0.0.0 --port 8000

# Readiness
curl -s https://api.haneat.app/api/v1/system/readiness | jq

# Flutter dev
flutter run --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001

# Flutter release
./scripts/build_ios_release.sh https://api.haneat.app
./scripts/build_android_release.sh https://api.haneat.app

# Launch verify (health + readiness + smoke)
./scripts/verify_launch.sh http://127.0.0.1:5001

# Staging build
./scripts/build_staging_ios.sh https://staging-api.haneat.app
```
