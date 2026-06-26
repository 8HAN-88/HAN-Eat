# Включение push (FCM + APNs)

Проект Firebase: **han-eat** (`PROJECT_ID` в `GoogleService-Info.plist`).

## 1. Service Account (backend)

1. Откройте [Service accounts](https://console.firebase.google.com/project/han-eat/settings/serviceaccounts/adminsdk).
2. **Generate new private key** → сохраните JSON (не коммитьте в git).
3. Запустите:

```bash
bash scripts/enable_firebase_push_prod.sh ~/Downloads/han-eat-xxxxx.json
```

Скрипт:

- копирует ключ в `backend/firebase-credentials.json` (локально, в `.gitignore`);
- выставляет `FIREBASE_*` в `backend/.env`;
- заливает ключ на сервер `/etc/haneat/firebase-credentials.json`;
- обновляет `/root/HAN-Eat/backend/.env` и перезапускает `haneat-api`.

Проверка:

```bash
cd backend && python3 scripts/check_firebase_config.py
curl -s https://api.haneat.app/api/v1/system/readiness | jq .infrastructure.firebase
```

Ожидается: `"push_ready": true`.

## 2. iOS (APNs)

Без этого push на iPhone **не дойдут**, даже при рабочем backend.

1. [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) → Keys → **+** → Apple Push Notifications service (APNs).
2. Скачайте `.p8`, запомните **Key ID** и **Team ID**.
3. Firebase Console → **Project settings** → **Cloud Messaging** → Apple app → загрузите APNs Authentication Key.

В Xcode для target Runner должны быть включены **Push Notifications** и **Background Modes → Remote notifications** (в `Info.plist` уже есть `UIBackgroundModes` → `remote-notification`).

## 3. Android

`android/app/google-services.json` уже в проекте — дополнительных шагов обычно не нужно.

## SSH: `Connection closed by 89.19.216.60 port 22`

Локальная часть скрипта уже OK (`Firebase push ready`). Prod API пока без push, пока ключ не на сервере.

**Что сделать без SSH с Mac:**

1. [Timeweb](https://timeweb.cloud) → ваш сервер → **Консоль** (терминал в браузере).
2. Создайте каталог и загрузите JSON (через SFTP в панели или `nano` + вставка):

```bash
mkdir -p /etc/haneat
chmod 700 /etc/haneat
nano /etc/haneat/firebase-credentials.json
# вставьте содержимое han-eat-firebase-adminsdk-....json, сохраните
chmod 600 /etc/haneat/firebase-credentials.json
```

3. Откройте env API:

```bash
nano /root/HAN-Eat/backend/.env
```

Добавьте или замените строки:

```env
FIREBASE_ENABLED=true
FIREBASE_CREDENTIALS_PATH=/etc/haneat/firebase-credentials.json
FIREBASE_PROJECT_ID=han-eat
```

4. Перезапуск:

```bash
systemctl restart haneat-api
systemctl status haneat-api --no-pager
```

5. С Mac проверьте:

```bash
curl -s https://api.haneat.app/api/v1/system/readiness | python3 -m json.tool
```

Нужно: `"push_ready": true`.

**Если хотите починить SSH с Mac:** Timeweb → сервер → SSH-ключи / firewall (порт 22), убедитесь что в `authorized_keys` есть ваш `~/.ssh/haneat_timeweb.pub`.

---

## 4. Тест

1. Установите сборку на устройство, войдите в аккаунт, разрешите уведомления.
2. В БД у пользователя должен появиться `fcm_token` (профиль обновляется автоматически).
3. Вызовите событие с другого аккаунта (лайк, комментарий) или админский тест push из backend.

## Переменные окружения

| Переменная | Пример |
|------------|--------|
| `FIREBASE_ENABLED` | `true` |
| `FIREBASE_CREDENTIALS_PATH` | `/etc/haneat/firebase-credentials.json` (prod) |
| `FIREBASE_PROJECT_ID` | `han-eat` |

Альтернатива файлу: `FIREBASE_CREDENTIALS_JSON` — одна строка JSON (удобно в CI, не в git).
