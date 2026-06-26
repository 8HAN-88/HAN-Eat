# Т-Банк: СБП и автосписания подписок

> **Фаза 3** по [PAYMENTS_ROADMAP.md](PAYMENTS_ROADMAP.md) — после релиза на ЮKassa и оформления ИП.

Основной платёжный провайдер для RU/BY/KZ при `TBANK_ENABLED=true`.

## Переменные окружения (backend/.env)

```env
TBANK_ENABLED=true
TBANK_TERMINAL_KEY=...
TBANK_PASSWORD=...
TBANK_API_URL=https://securepay.tinkoff.ru/v2
TBANK_SBP_RECURRING_ENABLED=true

API_PUBLIC_BASE_URL=https://api.haneat.app
FRONTEND_URL=https://haneat.app

# ЮKassa — выключить при переходе на Т-Банк
YOOKASSA_ENABLED=false
```

## Webhook

В личном кабинете интернет-эквайринга укажите:

`https://api.haneat.app/api/v1/payments/webhook/tbank`

Проверка подписи: поле `Token` в теле уведомления (SHA-256 по правилам API v2).

## Как работает оплата

1. **Первая оплата:** `POST /api/v1/payments/checkout` → `Init` с `DATA.QR=true`, `Recurrent=Y`, `CustomerKey=user_id` → пользователь платит по СБП → webhook `CONFIRMED` → `RebillId` в `users.tbank_rebill_id`, подписка `active`, `auto_renew=true`.
2. **Продление:** фоновая задача за ~24 ч до `expires_at` → `Init` + `Charge(RebillId)` → webhook → продление периода.
3. **Отмена автопродления:** `POST /api/v1/subscriptions/cancel` — сбрасывает `tbank_rebill_id` и `auto_renew`.

## Миграция БД

```bash
cd backend && alembic upgrade head
```

Миграция `040_tbank_rebill_v1`: колонка `users.tbank_rebill_id`.

## Проверка конфигурации

```bash
cd backend && python3 scripts/check_tbank_config.py
curl https://api.haneat.app/api/v1/payments/readiness
```

## Тестовый терминал

Используйте тестовый `TerminalKey` из ЛК Т-Банка. После тестовой оплаты проверьте логи webhook и `/api/v1/subscriptions/status`.

## Возвраты

Админ: `POST /api/v1/payments/admin/refund` — для `payment_provider=tbank` вызывается `Cancel` API Т-Банка.

Пользователь: `POST /api/v1/payments/refund-request` (тикет в поддержку).

## ЮKassa (legacy)

При `TBANK_ENABLED=false` и `YOOKASSA_ENABLED=true` checkout остаётся на ЮKassa. Оба провайдера не должны быть активны одновременно в production без явной необходимости.
