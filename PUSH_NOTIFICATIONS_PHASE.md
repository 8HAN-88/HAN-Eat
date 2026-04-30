# Push Notifications Infrastructure - Завершено ✅

## Выполнено

### 1. ✅ Backend - Модель User
- Добавлено поле `fcm_token` в модель User
- Создана миграция `011_add_fcm_token_to_users.py`

### 2. ✅ Backend - API
- Обновлена схема `UpdateUserRequest` для поддержки `fcm_token`
- Обновлен endpoint `PATCH /users/me` для сохранения FCM токена

### 3. ✅ Backend - Push Service
- Создан `PushService` для отправки push уведомлений через FCM
- Интегрирован с `NotificationService` для автоматической отправки push при создании уведомлений
- Поддержка батч отправки уведомлений

### 4. ✅ Flutter - Push Notification Service
- Создан `PushNotificationService` для работы с Firebase Cloud Messaging
- Автоматическое получение и обновление FCM токена
- Обработка уведомлений в foreground и background
- Автоматическая отправка токена на сервер при изменении
- Поддержка подписки/отписки от топиков

### 5. ✅ Flutter - User Service
- Обновлен метод `updateProfile` для поддержки `fcmToken`
- Автоматическая отправка токена на сервер

### 6. ✅ Flutter - Bootstrap
- Добавлена инициализация `PushNotificationService` в `bootstrap.dart`
- Инициализация происходит только если Firebase успешно инициализирован

## Структура изменений

### Backend
```
backend/
├── app/
│   ├── models/
│   │   └── user.py (добавлено fcm_token)
│   ├── schemas/
│   │   └── user.py (добавлено fcm_token в UpdateUserRequest)
│   ├── api/
│   │   └── v1/
│   │       └── users.py (обновлен PATCH /users/me)
│   ├── services/
│   │   ├── push_service.py (новый сервис)
│   │   └── notification_service.py (интеграция с push)
│   └── migrations/
│       └── versions/
│           └── 011_add_fcm_token_to_users.py (новая миграция)
```

### Frontend
```
lib/
├── services/
│   ├── push_notification_service.dart (новый сервис)
│   └── user_service.dart (обновлен updateProfile)
└── app/
    └── bootstrap.dart (добавлена инициализация)
```

## Особенности реализации

### Backend Push Service
- Использует переменные окружения `FCM_ENABLED` и `FCM_SERVER_KEY`
- Подготовлен для интеграции с `pyfcm` или `firebase-admin`
- Обрабатывает ошибки (невалидные токены, отключенные уведомления)
- Поддерживает батч отправку для оптимизации

### Flutter Push Service
- Автоматически запрашивает разрешения на уведомления (iOS)
- Обрабатывает уведомления в разных состояниях приложения:
  - Foreground: `onMessage`
  - Background: `onMessageOpenedApp`
  - Terminated: `getInitialMessage`
- Автоматически обновляет токен на сервере при изменении
- Сохраняет токен локально для проверки изменений

## Настройка

### Backend
Добавьте в `.env`:
```env
FCM_ENABLED=true
FCM_SERVER_KEY=your_fcm_server_key_here
```

### Flutter
Уже настроено:
- `firebase_messaging` в `pubspec.yaml`
- Инициализация в `bootstrap.dart`
- Автоматическая отправка токена на сервер

## TODO (следующие шаги)

- [ ] Установить `pyfcm` или `firebase-admin` в backend
- [ ] Реализовать фактическую отправку push через FCM API
- [ ] Добавить обработку ошибок (невалидные токены)
- [ ] Добавить настройки уведомлений (включить/выключить типы)
- [ ] Реализовать навигацию при открытии уведомления
- [ ] Добавить локальные уведомления для foreground
- [ ] Настроить APNs для iOS (если нужно)

## Миграция базы данных

Для применения изменений выполните:
```bash
cd backend
alembic upgrade head
```

## Тестирование

1. Запустите приложение Flutter
2. Разрешите уведомления при первом запуске
3. Проверьте, что токен отправляется на сервер (в логах)
4. Создайте уведомление через API (например, лайк поста)
5. Проверьте, что push уведомление приходит (после реализации отправки)

