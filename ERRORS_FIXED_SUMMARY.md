# Исправленные ошибки

## Основные исправления

### 1. Модель Post (`lib/models/post.dart`)
- ✅ Добавлен геттер `isPinned`
- ✅ Добавлен геттер `idString` для совместимости (int → String)
- ✅ Добавлен метод `fromFirestore` для создания из Firestore документов
- ✅ Исправлены типы в `PostReactions` (num → int)
- ✅ Добавлено поле `dislikes` в `PostReactions`

### 2. Новые типы (`lib/models/post_types.dart`)
- ✅ Создан enum `PostType` (text, photo, recipe, reel, link, photoGallery, repost)
- ✅ Создан enum `PostStatus` (draft, published, pending, rejected, archived)
- ✅ Создан enum `FeedSortMode` (personalized, recent, popular, trending)

### 3. ApiService (`lib/services/api_service.dart`)
- ✅ Добавлены публичные методы: `uri()`, `jsonHeaders`, `ensureSuccess()`
- ✅ Позволяет использовать приватные методы из других сервисов

### 4. AuthService (`lib/services/auth_service.dart`)
- ✅ Добавлен singleton `instance`
- ✅ Добавлен геттер `currentUser`

### 5. UserService (`lib/services/user_service.dart`)
- ✅ Добавлен singleton `instance`
- ✅ Добавлен метод `loadPublicProfile(String userId)`

### 6. ModerationService (`lib/services/moderation_service.dart`)
- ✅ Добавлен метод `moderateText(String text)`
- ✅ Добавлен класс `ModerationResult`

## Оставшиеся проблемы

### Требуют ручного исправления:

1. **Использование `post.id` как String** - заменить на `post.idString` в:
   - `lib/features/community/presentation/post_interactions_widget.dart`
   - `lib/features/community/presentation/community_wall_screen.dart`
   - `lib/services/post_interactions_service.dart`
   - И других местах, где `post.id` используется как String

2. **Использование `PostType` и `PostStatus`** - добавить импорт:
   ```dart
   import '../models/post_types.dart';
   ```

3. **Использование `FeedSortMode`** - добавить импорт:
   ```dart
   import '../models/post_types.dart';
   ```

4. **Проблемы с конструктором Post** - некоторые места используют `authorId`, но модель использует `userId`

5. **Проблемы с `FeedService.getMainFeed`** - метод может не существовать или иметь другое имя

## Рекомендации

1. Замените все использования `post.id` (где ожидается String) на `post.idString`
2. Добавьте импорты `post_types.dart` где используются `PostType`, `PostStatus`, `FeedSortMode`
3. Проверьте все места, где используется `Post.fromFirestore` - теперь метод существует
4. Исправьте проблемы с `authorId` → `userId` в конструкторах Post

