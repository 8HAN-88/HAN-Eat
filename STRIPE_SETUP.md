# Настройка Stripe для подписок H.A.N. Plus

## Обзор

Интеграция Stripe позволяет пользователям покупать подписки H.A.N. Plus через безопасную платежную систему.

## Что реализовано

### Backend
- ✅ `PaymentService` - сервис для работы со Stripe
- ✅ API endpoints для создания checkout sessions
- ✅ Webhook обработка для событий Stripe
- ✅ Автоматическое создание подписок после оплаты
- ✅ Обработка продления и отмены подписок

### Frontend
- ✅ Экран подписки с выбором плана
- ✅ Интеграция с Stripe Checkout
- ✅ Экраны успешной/отмененной оплаты
- ✅ Проверка статуса подписки

## Настройка Stripe

### 1. Создание аккаунта Stripe

1. Зайдите на [stripe.com](https://stripe.com)
2. Создайте аккаунт или войдите
3. Перейдите в Dashboard

### 2. Создание продуктов и цен

1. В Stripe Dashboard перейдите в **Products**
2. Создайте продукт "H.A.N. Plus Monthly":
   - Name: `H.A.N. Plus Monthly`
   - Description: `Monthly subscription to H.A.N. Plus`
   - Pricing: Recurring, Monthly
   - Price: `2.99 USD` (или ваша цена)
   - Скопируйте **Price ID** (начинается с `price_`)

3. Создайте продукт "H.A.N. Plus Yearly":
   - Name: `H.A.N. Plus Yearly`
   - Description: `Yearly subscription to H.A.N. Plus`
   - Pricing: Recurring, Yearly
   - Price: `29.99 USD` (или ваша цена)
   - Скопируйте **Price ID** (начинается с `price_`)

### 3. Получение API ключей

1. В Stripe Dashboard перейдите в **Developers** → **API keys**
2. Скопируйте:
   - **Publishable key** (начинается с `pk_test_` или `pk_live_`)
   - **Secret key** (начинается с `sk_test_` или `sk_live_`)

### 4. Настройка Webhooks

1. В Stripe Dashboard перейдите в **Developers** → **Webhooks**
2. Нажмите **Add endpoint**
3. Endpoint URL: `https://your-backend-url.com/api/v1/payments/webhook`
4. Выберите события для прослушивания:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Скопируйте **Signing secret** (начинается с `whsec_`)

### 5. Настройка Backend

Добавьте в `.env` файл backend:

```env
# Stripe настройки
STRIPE_ENABLED=true
STRIPE_SECRET_KEY=sk_test_...  # Ваш Secret Key
STRIPE_PUBLISHABLE_KEY=pk_test_...  # Ваш Publishable Key (для frontend, если нужно)
STRIPE_WEBHOOK_SECRET=whsec_...  # Ваш Webhook Secret
STRIPE_PRICE_ID_MONTHLY=price_...  # Price ID для месячной подписки
STRIPE_PRICE_ID_YEARLY=price_...  # Price ID для годовой подписки
FRONTEND_URL=http://localhost:8080  # URL вашего frontend приложения
```

### 6. Установка зависимостей

Stripe уже добавлен в `requirements.txt`:
```bash
pip install stripe==7.8.0
```

Или установите все зависимости:
```bash
cd backend
pip install -r requirements.txt
```

## Тестирование

### Тестовые карты Stripe

Для тестирования используйте тестовые карты:

- **Успешная оплата**: `4242 4242 4242 4242`
- **Требует аутентификации**: `4000 0025 0000 3155`
- **Отклонена**: `4000 0000 0000 0002`

Используйте:
- Любую будущую дату истечения (например, 12/34)
- Любой 3-значный CVC
- Любой почтовый индекс

### Проверка работы

1. Запустите backend сервер
2. Запустите Flutter приложение
3. Перейдите на экран подписки
4. Выберите план и нажмите "Купить"
5. В открывшемся Stripe Checkout используйте тестовую карту
6. После оплаты вы должны быть перенаправлены на экран успеха
7. Проверьте, что подписка активирована в приложении

## Production настройка

### 1. Переключение на Live режим

1. В Stripe Dashboard переключитесь на **Live mode**
2. Получите Live API ключи
3. Обновите `.env` файл с Live ключами
4. Создайте Live продукты и цены
5. Настройте Live webhook endpoint

### 2. Безопасность

- ✅ Webhook подпись проверяется автоматически
- ✅ Все платежи обрабатываются через Stripe (не храним данные карт)
- ✅ Используйте HTTPS для production
- ✅ Храните секретные ключи в безопасном месте

## API Endpoints

### POST `/api/v1/payments/checkout`
Создает Stripe Checkout Session

**Request:**
```json
{
  "plan": "monthly" | "yearly",
  "success_url": "optional",
  "cancel_url": "optional"
}
```

**Response:**
```json
{
  "session_id": "cs_test_...",
  "url": "https://checkout.stripe.com/...",
  "customer_email": "user@example.com"
}
```

### POST `/api/v1/payments/webhook`
Webhook endpoint для обработки событий Stripe (вызывается автоматически)

### GET `/api/v1/payments/prices`
Получить информацию о ценах подписок

**Response:**
```json
{
  "monthly": {
    "price": 2.99,
    "currency": "USD",
    "price_id": "price_...",
    "interval": "month"
  },
  "yearly": {
    "price": 29.99,
    "currency": "USD",
    "price_id": "price_...",
    "interval": "year"
  }
}
```

## Troubleshooting

### Проблема: Webhook не работает

**Решение:**
- Проверьте, что webhook URL доступен из интернета (используйте ngrok для локальной разработки)
- Проверьте, что `STRIPE_WEBHOOK_SECRET` правильный
- Проверьте логи backend для ошибок

### Проблема: Подписка не создается после оплаты

**Решение:**
- Проверьте, что webhook настроен правильно
- Проверьте логи backend
- Убедитесь, что события `checkout.session.completed` и `customer.subscription.created` включены в webhook

### Проблема: Ошибка "Stripe is not enabled"

**Решение:**
- Проверьте, что `STRIPE_ENABLED=true` в `.env`
- Проверьте, что `STRIPE_SECRET_KEY` установлен
- Проверьте, что `stripe` пакет установлен

## Дополнительные ресурсы

- [Stripe Documentation](https://stripe.com/docs)
- [Stripe Checkout](https://stripe.com/docs/payments/checkout)
- [Stripe Webhooks](https://stripe.com/docs/webhooks)
- [Stripe Testing](https://stripe.com/docs/testing)

