# Дорожная карта платежей HAN-Eat

Поэтапное подключение без лишних обязательств до проверки продукта.

## Фаза 1 — сейчас (до релиза)

**Цель:** доработать приложение, без обязательного приёма денег.

```env
TBANK_ENABLED=false
YOOKASSA_ENABLED=false
```

Оплата в приложении недоступна (или только тестовый стенд с ключами ЮKassa).

Если нужно проверить СБП локально — временно `YOOKASSA_ENABLED=true` + тестовые ключи, **всегда**:

```env
YOOKASSA_PAYMENT_METHOD=sbp
YOOKASSA_SBP_RECURRING_ENABLED=false
```

Только **разовая** оплата, без автопродления.

---

## Фаза 2 — после релиза в сторах

**Цель:** легальный приём подписок в РФ (самозанятый или ИП) через ЮKassa, только СБП, разовые платежи.

```env
TBANK_ENABLED=false
YOOKASSA_ENABLED=true
YOOKASSA_SHOP_ID=...
YOOKASSA_SECRET_KEY=...
YOOKASSA_PAYMENT_METHOD=sbp
YOOKASSA_SBP_RECURRING_ENABLED=false
```

Webhook в ЛК ЮKassa:

`https://api.haneat.app/api/v1/payments/webhook/yookassa`

Подробнее: [YOOKASSA_SBP_SETUP.md](../YOOKASSA_SBP_SETUP.md)

Пользователь платит каждый период **вручную** в разделе «Подписка».

---

## Фаза 3 — после раскрутки (ИП + Т-Банк)

**Цель:** ниже комиссия / автосписания СБП через рекуррент Т-Банка.

Требования: **ИП** (или ООО), договор эквайринга, рекуррент в ЛК банка.

```env
YOOKASSA_ENABLED=false
TBANK_ENABLED=true
TBANK_TERMINAL_KEY=...
TBANK_PASSWORD=...
TBANK_SBP_RECURRING_ENABLED=true
```

Webhook:

`https://api.haneat.app/api/v1/payments/webhook/tbank`

Подробнее: [TBANK_SBP_SETUP.md](TBANK_SBP_SETUP.md)

Обновить текст в приложении (`subscription_copy.dart`) про автопродление.

---

## Приоритет провайдера в коде

При `TBANK_ENABLED=true` checkout идёт через Т-Банк.  
Иначе при `YOOKASSA_ENABLED=true` — через ЮKassa.  
Иначе оплата недоступна.

Проверка: `cd backend && python3 scripts/check_yookassa_config.py` или `check_tbank_config.py`.
