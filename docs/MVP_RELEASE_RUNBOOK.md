# MVP → релиз HAN Eat (практический план)

Обновлено по состоянию prod API и smoke.

## Уже готово (можно релизить ядро)

| Область | Статус |
|---------|--------|
| API `https://api.haneat.app` | health OK, БД + Redis OK |
| Smoke launch | 14/14 passed (`python3 backend/scripts/smoke_launch.py`) |
| S3 / медиа | настроено |
| Перевод меню (f2f0617) | быстрый ответ ~1 с, `recipe_translation_*` в meta |
| Flutter | `1.0.0+1`, bundle `com.haneat.app`, Google Sign-In OK |
| Legal HTML | `/privacy`, `/terms` на API |
| Код | лента, каналы, меню, план, скан, избранное |

## Блокеры до «полного» MVP (сделать до публичного релиза)

### 1. Сервер — последний backend (обязательно)

На Timeweb:

```bash
cd /root/HAN-Eat
git fetch origin && git reset --hard origin/main
git log -1 --oneline   # ожидается f2f0617 или новее
cd backend && source venv/bin/activate
pip install -q -r requirements.txt
alembic upgrade head
sudo systemctl restart haneat-api
```

Проверка:

```bash
time curl -s "https://api.haneat.app/api/v1/recommendations?limit=3&language=ru&refresh=true" | head -c 200
curl -s https://api.haneat.app/api/v1/system/readiness | python3 -m json.tool
```

### 2. ЮKassa (оплата подписок)

Сейчас: `YOOKASSA_ENABLED=false` — в приложении оплата не работает.

В `backend/.env` на сервере:

- `YOOKASSA_ENABLED=true`
- `YOOKASSA_SHOP_ID`, `YOOKASSA_SECRET_KEY`
- `YOOKASSA_PAYMENT_METHOD=sbp` (или card)
- `API_PUBLIC_BASE_URL=https://api.haneat.app`

В ЛК ЮKassa webhook:

`https://api.haneat.app/api/v1/payments/webhook/yookassa`

```bash
sudo systemctl restart haneat-api
curl -s https://api.haneat.app/api/v1/system/readiness | grep -i yookassa
```

См. `docs/YOOKASSA_SBP_SETUP.md`, `docs/YOOKASSA_WEBHOOK.md`.

**MVP без оплаты (текущий план):** TestFlight / store с free + trial; оплата отключена до ссылки в сторе для ЮKassa. См. **`docs/RELEASE_V1_NO_PAYMENT.md`** — UI «Оплата скоро», `checkout_available: false`.

### 3. App Store — подписки (IAP)

Цифровой контент (AI, план) в iOS обычно требует **In-App Purchase**, не только ЮKassa в WebView.

- **RU-only / soft launch:** TestFlight + оплата через web (риск reject — см. `docs/SUBSCRIPTION_STORE_STRATEGY.md`)
- **Правильно для App Store:** StoreKit / RevenueCat + verify на backend

До ревью: Privacy/Terms с текстом про подписку и отмену.

### 4. Legal на домене

- [ ] `https://haneat.app/privacy` и `/terms` (см. `docs/LEGAL_PAGES_DEPLOY.md`)
- В App Store Connect указать те же URL

### 5. Push (опционально для v1.0.0)

Readiness: `firebase.enabled: false` — push на prod может не работать. Для MVP можно без push; для retention — настроить `FIREBASE_*` в `.env`.

---

## Релиз по шагам (рекомендуемый порядок)

### Шаг A — Backend prod (1–2 ч)

1. `git reset --hard origin/main` на сервере  
2. ЮKassa env (если нужны платежи)  
3. `smoke_launch.py` на prod — exit 0  

### Шаг B — TestFlight iOS (полдня)

```bash
./scripts/pre_testflight_check.sh
./scripts/build_ios_release.sh https://api.haneat.app
open build/ios/archive/Runner.xcarchive
# Xcode → Distribute App → App Store Connect
```

См. `docs/TESTFLIGHT.md`.

### Шаг C — Internal testing Android

```bash
./scripts/build_android_release.sh https://api.haneat.app
# Play Console → Internal testing → AAB
```

### Шаг D — Ручной прогон (1–2 ч)

Чеклист: `docs/LAUNCH_SMOKE.md`

Минимум:

- Гость: лента  
- Вход / регистрация  
- Меню: рекомендации без таймаута  
- Открыть рецепт Spoonacular: шаги на русском (AI)  
- Канал: пост с фото  
- Подписка (если ЮKassa включена)  

### Шаг E — App Store Connect

1. Скриншоты, описание, категория Food & Drink  
2. Privacy URL, Terms URL  
3. Internal TestFlight → 5–10 тестеров  
4. External beta — после стабилизации  

---

## Что сознательно не входит в MVP v1

- Чат / личные сообщения  
- IAP (если не успеваете — только RU web-оплата + риск по гайдлайнам)  
- Firestore-лента (в release отключена — OK)  

---

## Быстрые команды

```bash
# Prod smoke
BASE_URL=https://api.haneat.app python3 backend/scripts/smoke_launch.py

# iOS release
./scripts/build_ios_release.sh https://api.haneat.app

# Android release
./scripts/build_android_release.sh https://api.haneat.app
```

---

## Следующее действие (сегодня)

1. **Вы:** `git reset --hard origin/main` + restart на Timeweb  
2. **Вы:** решить: релиз с оплатой (ЮKassa) или TestFlight без оплаты на неделю  
3. **Я могу помочь:** включить ЮKassa в `.env.example` чеклист, правки UI «оплата недоступна», сборка IPA  

Когда сервер на `f2f0617+` и smoke зелёный — можно грузить TestFlight.
