# Дополнительные функции ленты

## ✅ Реализовано

### 1. Оффлайн кеш и синхронизация

#### `FeedCacheService` (`lib/services/feed_cache_service.dart`)

**Возможности:**
- Локальное хранение постов в SharedPreferences
- Автоматическое кеширование при загрузке ленты
- Поддержка разных режимов сортировки (Свежие/Для вас)
- Обновление отдельных постов в кеше
- Очистка кеша
- Проверка свежести кеша

**Использование:**
```dart
// Инициализация в bootstrap
await FeedCacheService.init();

// Кеширование постов
await FeedCacheService.instance.cachePosts(posts, sortMode: FeedSortMode.personalized);

// Получение кешированных постов
final cached = FeedCacheService.instance.getCachedPosts();

// Проверка, нужна ли синхронизация
if (FeedCacheService.instance.needsSync(maxAge: Duration(minutes: 5))) {
  // Загрузить свежие посты
}
```

#### `FeedSyncService` (`lib/services/feed_sync_service.dart`)

**Возможности:**
- Автоматическое определение онлайн/оффлайн режима
- Синхронизация с сервером с fallback на кеш
- Фоновая синхронизация
- Автоматическая синхронизация при появлении интернета
- Полная синхронизация и обновление ленты

**Использование:**
```dart
// Инициализация
await FeedSyncService.init();

// Получение ленты (с автоматической синхронизацией)
final posts = await FeedSyncService.instance.getFeed(
  sortMode: FeedSortMode.personalized,
  useCache: true,
);

// Принудительное обновление
final freshPosts = await FeedSyncService.instance.refreshFeed();
```

### 2. Модерация постов

#### `PostModerationService` (`lib/services/post_moderation_service.dart`)

**Возможности:**
- Автоматическая модерация при создании поста
- Очередь постов на модерацию
- Одобрение/отклонение/удаление постов
- Обработка жалоб пользователей
- Статистика модерации
- Логирование действий модераторов

**Действия модератора:**
- `approvePost()` - одобрить пост
- `rejectPost()` - отклонить пост с указанием причины
- `deletePost()` - удалить пост
- `restorePost()` - восстановить удаленный пост
- `handleReport()` - обработать жалобу

**Автоматическая модерация:**
```dart
// При создании поста
final status = await PostModerationService.moderatePost(post);
// Возвращает: PostStatus.published или PostStatus.pending
```

#### Экран модерации (`lib/features/moderation/presentation/moderation_queue_screen.dart`)

**Возможности:**
- Просмотр очереди постов на модерацию
- Превью постов с контентом
- Быстрые действия: одобрить/отклонить/удалить
- Диалог для указания причины отклонения
- Статистика постов

**Использование:**
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const ModerationQueueScreen(),
  ),
);
```

### 3. Интеграция с лентой

#### Обновленный `FeedController`

- Автоматическое использование оффлайн кеша
- Фоновая синхронизация
- Показ кешированных данных при оффлайне
- Обновление кеша при загрузке новых постов

## Архитектура

### Поток данных

```
User Action
    ↓
FeedController.loadFeed()
    ↓
FeedSyncService.getFeed()
    ↓
[Online?] → FeedService.getFeedCandidates() → FeedCacheService.cachePosts()
    ↓                                          ↓
[Offline?] → FeedCacheService.getCachedPosts()
    ↓
Display in UI
```

### Модерация

```
Post Creation
    ↓
PostModerationService.moderatePost()
    ↓
[Auto Check] → Pass → Published
    ↓
[Flagged] → Pending → Moderation Queue
    ↓
Moderator Action → Approve/Reject/Delete
```

## Настройки

### Список модераторов

Отредактируйте `lib/services/post_moderation_service.dart`:
```dart
static const List<String> moderatorUserIds = [
  'moderator1@example.com',
  'moderator2@example.com',
];
```

### Время жизни кеша

По умолчанию: 5 минут. Изменить в `FeedSyncService`:
```dart
needsSync(maxAge: Duration(minutes: 10))
```

## Firestore структура

### Коллекция `posts`
- Стандартные поля поста
- `status`: 'published' | 'pending' | 'rejected' | 'deleted'
- `reportCount`: число (количество жалоб)
- `moderatedAt`, `moderatedBy`: метаданные модерации

### Подколлекция `posts/{id}/reports`
- `reason`: причина жалобы
- `createdAt`: время
- `handledAt`, `handledBy`: обработка

### Коллекция `moderation_logs`
- Логи всех действий модераторов

## Будущие улучшения

1. **ML-модерация**
   - Интеграция с OpenAI/ML моделями
   - Детекция контента (nudity, hate speech)

2. **Улучшенный кеш**
   - Инкрементальная синхронизация
   - Оптимистичные обновления
   - Конфликт-резолюция

3. **Расширенная модерация**
   - Массовые действия
   - Шаблоны ответов
   - Автоматические правила

4. **Аналитика**
   - Метрики модерации
   - Время обработки
   - Статистика жалоб

