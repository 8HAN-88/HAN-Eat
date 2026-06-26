# Релиз v1.0 без оплаты → ЮKassa после публикации

Стратегия: сначала **TestFlight / App Store / Play** со ссылкой на приложение, затем подключение ЮKassa в ЛК (им нужен URL продукта в сторе).

## Фаза 1 — сейчас (вы здесь)

### Backend (prod)

```env
YOOKASSA_ENABLED=false
TBANK_ENABLED=false
```

- `GET /api/v1/payments/prices` — каталог тарифов + `checkout_available: false`
- `POST /api/v1/payments/checkout` — `503` с кодом `PAYMENTS_UNAVAILABLE`
- Пробный период `POST /api/v1/subscriptions/trial` — **работает** (для тестеров и early adopters)

Деплой перед билдом:

```bash
cd /root/HAN-Eat && git pull && cd backend && alembic upgrade head
sudo systemctl restart haneat-api
BASE_URL=https://api.haneat.app python3 backend/scripts/smoke_launch.py
```

Локально перед загрузкой в сторы:

```bash
./scripts/release_all_checks.sh
RUN_PROD_SMOKE=1 ./scripts/release_all_checks.sh   # + smoke на api.haneat.app
```

Ожидание smoke: **payments WARN** — нормально; auth/feed/legal — OK.

### Клиент

- Экран подписки: кнопка оплаты неактивна, текст «Оплата скоро», trial — если доступен
- Release-сборка: `./scripts/build_ios_release.sh https://api.haneat.app` (Google OAuth из `.env` автоматически)
- Стабильность / smoke на устройстве: [STABILITY.md](STABILITY.md)
- **Не** класть `OPENAI_API_KEY` в store-билд (только server-side)

### App Store Connect (без IAP на v1)

1. Создать приложение, bundle `com.haneat.app`
2. Privacy: `https://haneat.app/privacy` (или `https://api.haneat.app/privacy`)
3. Terms: `https://haneat.app/terms`
4. Скриншоты, описание, возрастной рейтинг
5. TestFlight → internal testers → ручной smoke (`docs/LAUNCH_SMOKE.md`)
6. После одобрения — **скопировать ссылку App Store** для ЮKassa

### Play Console

1. Internal testing, AAB из `build_android_release.sh`
2. Data safety + content rating
3. Ссылка на listing — для ЮKassa при необходимости

**Полный чеклист web + Play:** [RELEASE_WEB_AND_PLAY.md](RELEASE_WEB_AND_PLAY.md)

### Ручной smoke (обязательно, ~1–2 ч)

См. `docs/LAUNCH_SMOKE.md`:

- [ ] Гость: лента, каналы
- [ ] Регистрация / Google
- [ ] Меню, рецепт, AI-перевод шагов
- [ ] AI scan (лимиты free)
- [ ] Meal plan free (cooldown)
- [ ] Подписка: **нет** активной кнопки СБП; trial — если нужно
- [ ] Пост/рецепт с фото

### iOS перед upload

```bash
./scripts/pre_testflight_check.sh
```

- Apple Distribution certificate
- `ios/Runner/GoogleService-Info.plist` на месте
- ATS: без `NSAllowsArbitraryLoads` (release)

---

## Фаза 2 — сразу после публикации в сторе

1. В App Store Connect / Play — взять **публичную ссылку** на приложение
2. ЮKassa: магазин + webhook `https://api.haneat.app/api/v1/payments/webhook/yookassa`
3. На сервере:

```env
YOOKASSA_ENABLED=true
YOOKASSA_SHOP_ID=...
YOOKASSA_SECRET_KEY=...
YOOKASSA_PAYMENT_METHOD=sbp
YOOKASSA_SBP_RECURRING_ENABLED=false
```

4. `sudo systemctl restart haneat-api`
5. Проверка: `curl -s https://api.haneat.app/api/v1/payments/prices | jq .checkout_available` → `true`
6. Тестовая оплата СБП → deep link `haneat://subscription/success`

Подробнее: `YOOKASSA_SBP_SETUP.md`, `docs/PAYMENTS_ROADMAP.md`.

---

## Push (FCM) — включить одной командой

1. [Firebase Console](https://console.firebase.google.com/project/han-eat/settings/serviceaccounts/adminsdk) → **Generate new private key** (JSON).
2. `bash scripts/enable_firebase_push_prod.sh ~/Downloads/ваш-ключ.json`
3. **iOS:** Firebase → Cloud Messaging → загрузить **APNs Key** (.p8).
4. Проверка prod: `curl -s https://api.haneat.app/api/v1/system/readiness | jq .infrastructure.firebase`

Клиент уже запрашивает разрешение и шлёт `fcm_token` на API; без шага 1–2 сервер не может отправлять push.

---

## Что не входит в v1

- IAP (StoreKit) — отдельно, если выходите за пределы RU web-оплаты
- Реклама — не в коде v1
- Автопродление СБП — фаза 3

---

## Быстрые команды

```bash
./scripts/pre_testflight_check.sh
./scripts/build_ios_release.sh https://api.haneat.app
./scripts/build_android_release.sh https://api.haneat.app
BASE_URL=https://api.haneat.app python3 backend/scripts/smoke_launch.py
```
