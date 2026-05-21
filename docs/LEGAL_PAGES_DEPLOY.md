# Публикация Privacy / Terms

Исходники: `static/legal/privacy.html`, `static/legal/terms.html`

## Вариант A — с API (быстрый тест)

После деплоя backend:

- `https://api.haneat.app/privacy`
- `https://api.haneat.app/terms`

Проксируйте с основного домена (nginx):

```nginx
location /privacy {
    proxy_pass https://api.haneat.app/privacy;
}
location /terms {
    proxy_pass https://api.haneat.app/terms;
}
```

## Вариант B — статика на haneat.app

Скопируйте HTML на хостинг:

```bash
rsync -av static/legal/ user@haneat.app:/var/www/haneat/legal/
```

Nginx:

```nginx
location = /privacy {
    alias /var/www/haneat/legal/privacy.html;
}
location = /terms {
    alias /var/www/haneat/legal/terms.html;
}
```

## App Store Connect

В карточке приложения укажите:

- Privacy Policy URL: `https://haneat.app/privacy`
- Terms: `https://haneat.app/terms` (если требуется)

Ссылки в приложении: `lib/core/config/legal_urls.dart`
