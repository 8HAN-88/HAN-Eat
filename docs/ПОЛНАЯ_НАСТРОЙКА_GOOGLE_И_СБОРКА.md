# Полная настройка Google Sign-In и сборки (без поломок)

Делайте **по порядку**. После каждого блока — команда проверки.

---

## Блок 0. Что должно совпадать (иначе ломается)

| Место | Значение |
|-------|----------|
| Android package | `com.haneat.app` |
| iOS bundle (Xcode) | `com.haneat.app` |
| Firebase Android app | `com.haneat.app` |
| Firebase iOS app | **`com.haneat.app`** (не `com.example.hanEat`) |

Сейчас в `GoogleService-Info.plist` указан **`com.example.hanEat`** — это нужно исправить в Firebase.

---

## Блок 1. Firebase Console

### 1.1 Включить Google

1. [Firebase Console](https://console.firebase.google.com) → проект **HAN Eat**
2. Слева **Authentication** → **Sign-in method**
3. **Google** → **Enable** → выберите support email → **Save**

### 1.2 iOS-приложение с правильным bundle

1. Шестерёнка → **Project settings** → **Your apps**
2. Если iOS app с bundle `com.example.hanEat` — лучше **Add app** → **iOS**
3. Bundle ID: **`com.haneat.app`**
4. Скачайте **GoogleService-Info.plist**
5. Замените файл: `ios/Runner/GoogleService-Info.plist`

### 1.3 Android: SHA-1

**На Mac в терминале:**

```bash
mkdir -p ~/.android
keytool -genkey -v -keystore ~/.android/debug.keystore -storepass android \
  -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"

cd /Users/han/HAN-Eat
./scripts/android_print_sha1.sh
```

Скопируйте строку **SHA1:** (формат `AA:BB:CC:...`).

**В Firebase:**

1. Project settings → **han_eat (android)** (`com.haneat.app`)
2. **SHA certificate fingerprints** → **Add fingerprint** → вставить SHA-1 → Save
3. (Рекомендуется) добавить и **SHA-256**, если скрипт показал

### 1.4 Скачать конфиги заново

После SHA-1 **обязательно** перекачайте:

- Android → **google-services.json** → `android/app/google-services.json`  
  Проверка: в файле `"oauth_client": [ {...} ]` — **не пустой массив**
- iOS → **GoogleService-Info.plist** → `ios/Runner/GoogleService-Info.plist`  
  Проверка: `BUNDLE_ID` = `com.haneat.app`

### 1.5 Web Client ID (для backend)

Нужен клиент типа **Web application** (не только iOS/Android).

1. [Google Cloud Console](https://console.cloud.google.com/) → проект **han-eat**
2. **APIs & Services** → **Credentials**
3. **OAuth 2.0 Client IDs** → клиент **Web client** (или создайте)
4. Скопируйте **Client ID** (`....apps.googleusercontent.com`)

Этот ID — для `GOOGLE_WEB_CLIENT_ID` и `GOOGLE_OAUTH_CLIENT_IDS`.

---

## Блок 2. Файлы `.env`

### Корень проекта: `/Users/han/HAN-Eat/.env`

```env
GOOGLE_WEB_CLIENT_ID=ВАШ_WEB_CLIENT_ID.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=834367201092-hf2n8s69fbhc32ekp88nho5vdhcoq6b3.apps.googleusercontent.com
```

`GOOGLE_IOS_CLIENT_ID` — из `GoogleService-Info.plist` → ключ `CLIENT_ID` (после скачивания нового plist значение может измениться).

### Backend: `/Users/han/HAN-Eat/backend/.env`

```env
GOOGLE_OAUTH_CLIENT_IDS=ВАШ_WEB_CLIENT_ID.apps.googleusercontent.com
SKIP_GOOGLE_ID_TOKEN_VERIFICATION=false
```

**Web** и **backend** — один и тот же Web Client ID.

---

## Блок 3. iOS URL scheme

```bash
cd /Users/han/HAN-Eat
python3 scripts/ios_apply_google_url_scheme.py
```

Должно: `OK: добавлен CFBundleURLSchemes → com.googleusercontent.apps....`

---

## Блок 4. Проверки (все должны пройти)

```bash
cd /Users/han/HAN-Eat
python3 scripts/verify_google_signin.py
```

Exit code **0** — Google настроен.

```bash
cd backend
alembic upgrade head
uvicorn app.main:app --host 127.0.0.1 --port 5001 --reload
```

В другом терминале:

```bash
cd /Users/han/HAN-Eat
./scripts/verify_launch.sh http://127.0.0.1:5001
```

---

## Блок 5. Запуск приложения

```bash
cd /Users/han/HAN-Eat
flutter pub get
flutter run -d "iPhone 17" --dart-define=HANEAT_API_BASE=http://127.0.0.1:5001
```

На экране входа должна быть кнопка **«Войти через Google»** (если `GOOGLE_WEB_CLIENT_ID` задан).

---

## Блок 6. Release / TestFlight (позже)

```bash
./scripts/pre_testflight_check.sh
./scripts/build_ios_release.sh https://api.haneat.app
```

См. `docs/TESTFLIGHT.md`

---

## Частые ошибки

| Симптом | Причина | Решение |
|---------|---------|---------|
| `oauth_client: []` в json | Нет SHA-1 | Блок 1.3–1.4 |
| Google не возвращается в app (iOS) | Нет URL scheme | Блок 3 |
| 401 на `/auth/google` | Неверный Web Client ID в backend | Блок 2 |
| Кнопки Google нет | Нет `GOOGLE_WEB_CLIENT_ID` в `.env` | Блок 2 |
| `developer_error` Android | Старый json без oauth | Перескачать json после SHA-1 |

---

## Чеклист «всё готово»

- [ ] `python3 scripts/verify_google_signin.py` → 0
- [ ] `./scripts/verify_launch.sh` → OK
- [ ] Вход через Google на симуляторе/телефоне работает
- [ ] `GoogleService-Info.plist` → `BUNDLE_ID` = `com.haneat.app`
- [ ] `google-services.json` → `oauth_client` не пустой
