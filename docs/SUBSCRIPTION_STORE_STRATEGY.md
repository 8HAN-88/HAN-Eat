# Подписки: App Store vs ЮKassa

## Текущая реализация

- Оплата через **ЮKassa** (web checkout + deep link `haneat://subscription/...`).
- Entitlements на **backend** (`SubscriptionService`).

## Рекомендация по рынкам

| Рынок | Канал | Примечание |
|-------|--------|------------|
| Россия / web | ЮKassa | Уже реализовано |
| App Store (глобальный) | **StoreKit 2 / IAP** | Apple Guideline 3.1.1 — цифровой контент в приложении |
| Google Play (глобальный) | **Play Billing** | Аналогично для цифровых подписок |

## План миграции (если выходите в US/EU stores)

1. Добавить `in_app_purchase` / RevenueCat.
2. Backend: эндпоинты verify receipt (Apple/Google) + связка `store_transaction_id`.
3. В UI iOS/Android скрыть кнопку «Оплатить картой» там, где требуется IAP; оставить ЮKassa на web и RU-сборках при отдельной политике (юрист + App Review).

## До релиза в TestFlight

- [ ] Решение зафиксировано в App Store Connect (IAP product IDs или «Reader app» / web-only исключения — обычно не подходит для meal plan AI).
- [ ] Privacy Policy и Terms с описанием подписки и отмены.
- [ ] Restore purchases (если IAP).
