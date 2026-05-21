# ЮKassa: webhook и возврат в приложение

## Webhook

В личном кабинете ЮKassa укажите URL:

```
https://<ваш-api>/api/v1/payments/webhook/yookassa
```

Проверка готовности:

```bash
curl -s https://api.haneat.app/api/v1/system/readiness | jq
```

Переменные backend (`.env`):

- `YOOKASSA_ENABLED=true`
- `YOOKASSA_SHOP_ID`, `YOOKASSA_SECRET_KEY`
- `API_PUBLIC_BASE_URL=https://api.haneat.app` (публичный HTTPS, не localhost)

## Возврат после оплаты

| Платформа | success_url | cancel_url |
|-----------|-------------|------------|
| Web | `https://haneat.app/subscription/success?...` | `/subscription/cancel` |
| iOS/Android | `haneat://subscription/success` | `haneat://subscription/cancel` |

Deep link обрабатывается в `parseDeepLinkToGoPath` → экраны успеха/отмены подписки.

## Локальная отладка webhook

Используйте ngrok/cloudflared:

```bash
cloudflared tunnel --url http://127.0.0.1:5001
# В ЮKassa: https://<tunnel>.trycloudflare.com/api/v1/payments/webhook/yookassa
```
