# Push уведомления - Документация

## Обзор

Система push уведомлений использует Firebase Cloud Messaging (FCM) для отправки уведомлений на Android и iOS устройства. Firebase Admin SDK обеспечивает единый API для обеих платформ.

## Архитектура

### Компоненты

1. **PushService**: Сервис для отправки push уведомлений
2. **Firebase Admin SDK**: Библиотека для работы с FCM и APNs
3. **User Model**: Хранит FCM токены и информацию о платформе устройства

### Платформы

- **Android**: Использует FCM напрямую
- **iOS**: Использует APNs через FCM (Firebase автоматически маршрутизирует)

## Настройка

### 1. Firebase проект

1. Создайте проект в [Firebase Console](https://console.firebase.google.com/)
2. Добавьте Android и iOS приложения в проект
3. Скачайте файл credentials (JSON) для серверного приложения

### 2. Конфигурация

Добавьте в `.env`:

```env
# Firebase
FIREBASE_ENABLED=true
FIREBASE_CREDENTIALS_PATH=/path/to/firebase-credentials.json
FIREBASE_PROJECT_ID=your-project-id

# Или используйте переменную окружения с JSON
FIREBASE_CREDENTIALS_JSON='{"type":"service_account",...}'
```

### 3. iOS настройка (APNs)

1. В Firebase Console добавьте iOS приложение
2. Загрузите APNs ключ или сертификат
3. Firebase автоматически использует APNs для iOS устройств

### 4. Android настройка (FCM)

1. В Firebase Console добавьте Android приложение
2. Добавьте `google-services.json` в Android проект
3. FCM будет работать автоматически

## Использование

### Отправка одиночного уведомления

```python
from app.services.push_service import get_push_service
from app.models.user import User
from app.models.notification import Notification

push_service = get_push_service()

# Отправка уведомления
success = push_service.send_push_notification(
    user=user,
    notification=notification,
    data={"custom_key": "custom_value"}
)
```

### Отправка батча уведомлений

```python
notifications = [
    (user1, notification1),
    (user2, notification2),
    # ... до 500 за раз
]

success_count = push_service.send_batch_push_notifications(
    notifications=notifications,
    data={"custom_key": "custom_value"}
)
```

## Модель данных

### User Model

```python
class User:
    fcm_token: str  # FCM токен (для Android и iOS)
    device_platform: str  # android | ios | web
```

### Notification Model

```python
class Notification:
    type: str  # like | comment | follow | repost | mention | system
    title: str
    body: str
    entity_type: str  # post | comment | user | channel
    entity_id: int
    actor_id: int  # ID пользователя, который вызвал уведомление
```

## Формат уведомлений

### Android (FCM)

```json
{
  "notification": {
    "title": "Новый лайк",
    "body": "Иван Иванов лайкнул ваш пост"
  },
  "data": {
    "type": "like",
    "entity_type": "post",
    "entity_id": "123",
    "actor_id": "456"
  },
  "android": {
    "priority": "high",
    "notification": {
      "channel_id": "default",
      "sound": "default"
    }
  }
}
```

### iOS (APNs)

```json
{
  "notification": {
    "title": "Новый лайк",
    "body": "Иван Иванов лайкнул ваш пост"
  },
  "data": {
    "type": "like",
    "entity_type": "post",
    "entity_id": "123",
    "actor_id": "456"
  },
  "apns": {
    "payload": {
      "aps": {
        "alert": {
          "title": "Новый лайк",
          "body": "Иван Иванов лайкнул ваш пост"
        },
        "badge": 1,
        "sound": "default",
        "content-available": true
      }
    },
    "headers": {
      "apns-priority": "10"
    }
  }
}
```

## Обработка ошибок

### Недействительные токены

Если токен больше не действителен (например, приложение удалено), Firebase вернет `UnregisteredError`. В этом случае нужно удалить токен из БД:

```python
try:
    push_service.send_push_notification(user, notification)
except messaging.UnregisteredError:
    # Удалить токен из БД
    user.fcm_token = None
    db.commit()
```

### Ограничения

- **Батч**: До 500 сообщений за раз
- **Размер данных**: До 4KB для data payload
- **Размер notification**: До 2KB для title и body

## Типы уведомлений

1. **like**: Кто-то лайкнул пост
2. **comment**: Кто-то прокомментировал пост
3. **follow**: Кто-то подписался на вас
4. **repost**: Кто-то репостнул ваш пост
5. **mention**: Вас упомянули в комментарии
6. **system**: Системное уведомление

## Настройки уведомлений

Пользователи могут управлять настройками уведомлений через `NotificationPreferences`:

- Включить/выключить push уведомления
- Включить/выключить конкретные типы уведомлений
- Настройки применяются перед отправкой

## Производительность

### Оптимизации

1. **Батчинг**: Отправка до 500 уведомлений за раз
2. **Асинхронная обработка**: Использование очередей для больших объемов
3. **Кэширование**: Кэширование токенов и настроек

### Мониторинг

- Логирование успешных отправок
- Отслеживание ошибок
- Метрики доставки

## Безопасность

1. **Токены**: Хранятся в зашифрованном виде в БД
2. **Валидация**: Проверка токенов перед отправкой
3. **Очистка**: Автоматическое удаление недействительных токенов

## Тестирование

### Тестовые токены

Для тестирования можно использовать тестовые токены из Firebase Console или эмуляторы устройств.

### Логирование

Все операции логируются для отладки:

```python
logger.info(f"Push notification sent to user {user.id}")
logger.error(f"Failed to send push notification: {e}")
```

## Troubleshooting

### Проблемы с iOS

1. Проверьте APNs ключ/сертификат в Firebase Console
2. Убедитесь, что bundle ID совпадает
3. Проверьте настройки capabilities в Xcode

### Проблемы с Android

1. Проверьте `google-services.json` в проекте
2. Убедитесь, что Firebase SDK инициализирован
3. Проверьте разрешения в AndroidManifest.xml

### Общие проблемы

1. **Токен не работает**: Удалите и пересоздайте токен
2. **Уведомления не приходят**: Проверьте настройки уведомлений пользователя
3. **Ошибки Firebase**: Проверьте credentials и проект

