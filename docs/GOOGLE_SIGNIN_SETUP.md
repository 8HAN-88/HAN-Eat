# Google Sign-In — пошаговая настройка

## 1. Firebase Console

1. Проект **han-eat** → **Authentication** → **Sign-in method** → **Google** → Enable
2. **Project settings** → ваши приложения:
   - Android: package `com.haneat.app`
   - iOS: bundle `com.haneat.app`
3. Скачайте:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist` (из `GoogleService-Info.plist.example` не подходит — нужен реальный файл)

## 2. SHA-1 (Android)

```bash
./scripts/android_print_sha1.sh
```

Добавьте **SHA-1** и **SHA-256** в Firebase → Android app → Fingerprints.  
Скачайте `google-services.json` заново — в `oauth_client` не должно быть пустого массива.

## 3. iOS URL scheme

Из `GoogleService-Info.plist` возьмите `REVERSED_CLIENT_ID` и добавьте в `ios/Runner/Info.plist` → `CFBundleURLSchemes` (рядом с `haneat`).

Или из `.env`: `GOOGLE_IOS_CLIENT_ID` → `GoogleAuthConfig.iosReversedClientId`.

## 4. Переменные окружения

**Корень Flutter (`.env`):**

```env
GOOGLE_WEB_CLIENT_ID=123456789-xxxxx.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=123456789-yyyyy.apps.googleusercontent.com
```

**Backend (`backend/.env`):**

```env
GOOGLE_OAUTH_CLIENT_IDS=123456789-xxxxx.apps.googleusercontent.com
SKIP_GOOGLE_ID_TOKEN_VERIFICATION=false
```

`GOOGLE_WEB_CLIENT_ID` — тип **Web application** в Google Cloud (тот же ID в `GOOGLE_OAUTH_CLIENT_IDS`).

## 5. Автопроверка

```bash
python3 scripts/verify_google_signin.py
```

После добавления `GoogleService-Info.plist`:

```bash
python3 scripts/ios_apply_google_url_scheme.py
```

Backend readiness:

```bash
curl -s http://127.0.0.1:5001/api/v1/auth/google/readiness | jq
```

## 6. Проверка в приложении

```bash
cd backend && uvicorn app.main:app --port 5001
flutter run -d <device> --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001
```

На экране входа: кнопка Google → успешный redirect → JWT с backend.

Ошибки:

| Симптом | Решение |
|---------|---------|
| `oauth_client` пустой в json | SHA-1 + перескачать google-services.json |
| iOS не возвращается в app | REVERSED_CLIENT_ID в Info.plist |
| 401 от `/auth/google` | `GOOGLE_OAUTH_CLIENT_IDS` на backend |
| `developer_error` Android | package name + SHA-1 |
