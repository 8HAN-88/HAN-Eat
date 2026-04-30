# Permissions & Access Control - Завершено ✅

## Выполнено

### 1. ✅ Модель User
- Добавлены поля `is_admin` и `is_moderator` в модель User
- Поля имеют значение по умолчанию `False`
- Создана миграция `010_add_is_admin_is_moderator_to_users.py`

### 2. ✅ API Dependencies
- Добавлен `get_current_admin_required` - проверка прав админа
- Добавлен `get_current_moderator_required` - проверка прав модератора или админа
- Оба возвращают HTTP 403 при отсутствии прав

### 3. ✅ Moderation API
- Все endpoints модерации теперь требуют прав модератора/админа
- `GET /moderation/pending` - только для модераторов/админов
- `POST /moderation/{id}/approve` - только для модераторов/админов
- `POST /moderation/{id}/reject` - только для модераторов/админов

### 4. ✅ Support API
- `POST /support/tickets/{id}/resolve` - только для админов
- `GET /support/admin/tickets` - только для админов

### 5. ✅ Flutter User Model
- Добавлены поля `isAdmin` и `isModerator` в модель User
- Обновлен `fromJson` и `toJson` для поддержки новых полей

### 6. ✅ Settings Screen
- Пункт "Модерация" показывается только для админов/модераторов
- Проверка прав выполняется при загрузке экрана

## Структура изменений

### Backend
```
backend/
├── app/
│   ├── models/
│   │   └── user.py (добавлены is_admin, is_moderator)
│   ├── api/
│   │   ├── dependencies.py (добавлены проверки прав)
│   │   └── v1/
│   │       ├── moderation.py (обновлены зависимости)
│   │       └── support.py (обновлены зависимости)
│   └── migrations/
│       └── versions/
│           └── 010_add_is_admin_is_moderator_to_users.py (новая миграция)
```

### Frontend
```
lib/
├── services/
│   └── auth_service.dart (обновлена модель User)
└── features/
    └── settings/
        └── presentation/
            └── settings_screen.dart (условное отображение модерации)
```

## Особенности реализации

### Проверка прав доступа
- **Админ**: `is_admin == True`
- **Модератор**: `is_moderator == True` или `is_admin == True`
- Ошибка 403 Forbidden при отсутствии прав

### Безопасность
- Все проверки выполняются на уровне API
- Flutter UI скрывает элементы, но не защищает от прямых запросов
- Основная защита на backend

## Миграция базы данных

Для применения изменений выполните:
```bash
cd backend
alembic upgrade head
```

## Назначение прав пользователям

Для назначения прав админа/модератора можно использовать SQL:
```sql
-- Назначить админа
UPDATE users SET is_admin = true WHERE id = 1;

-- Назначить модератора
UPDATE users SET is_moderator = true WHERE id = 2;
```

Или через API (нужно будет добавить endpoint для этого).

## TODO (следующие шаги)

- [ ] Добавить API endpoint для назначения прав (только для суперадминов)
- [ ] Добавить проверку прав в Flutter перед навигацией
- [ ] Добавить UI для управления правами пользователей (админ панель)
- [ ] Добавить логирование действий админов/модераторов
- [ ] Добавить суперадмин роль (нельзя удалить/изменить)

