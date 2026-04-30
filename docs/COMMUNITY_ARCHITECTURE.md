# Архитектура системы сообществ, публикаций и доставки контента

## Обзор

Реализована полная система сообществ с функционалом, аналогичным VK, включающая:
1. **Сообщества** - полный функционал создания и управления
2. **Публикации контента** - посты, фото, видео, рилсы
3. **Механизм доставки контента** - автоматическое распределение в разные ленты

## Модели данных

### Community (`lib/models/community.dart`)
- Основная информация: название, аватар, обложка, описание
- Настройки: комментарии, сообщения, ссылки на соцсети
- Категории из еды
- Счётчики участников и постов

### CommunityMember (`lib/models/community.dart`)
- Роли: Owner, Admin, Editor, Moderator, Member
- Система прав для каждой роли
- История присоединения

### Post (`lib/models/post.dart`)
- Обновлена для поддержки:
  - `communityId` - привязка к сообществу
  - `isPinned` - закрепление поста
  - `isDeleted` - скрытие поста
  - Тип `reel` для коротких видео

### Reel (`lib/models/reel.dart`)
- Короткие видео от сообществ
- Оригинальное и транскодированное видео
- Статистика просмотров, лайков, комментариев

### FeedDelivery (`lib/models/feed_delivery.dart`)
- Управление доставкой контента в ленты:
  - `goesToMainFeed` - общая лента
  - `goesToReelsFeed` - лента рилсов
  - `goesToCommunityWall` - стена сообщества
  - `goesToSubscriptions` - лента подписок

## Сервисы

### CommunityManagementService (`lib/services/community_management_service.dart`)
**Функции:**
- Создание сообщества с аватаром и обложкой
- Обновление настроек сообщества
- Управление ролями участников
- Подписка/отписка от сообществ
- Поиск сообществ
- Получение стены сообщества

**Права доступа:**
- Owner/Admin: все права
- Editor: создание постов и рилсов
- Moderator: модерация комментариев
- Member: только просмотр

### PostPublicationService (`lib/services/post_publication_service.dart`)
**Функции:**
- Публикация постов (текст, фото, видео, ссылки, опросы)
- Публикация рилсов
- Автоматическая настройка доставки контента
- Закрепление/скрытие постов
- Удаление постов

**Логика публикации:**
- **Пост:** → стена сообщества + общая лента + подписчикам
- **Рилс:** → стена + общая лента + лента рилсов + подписчикам

### FeedDeliveryService (`lib/services/feed_delivery_service.dart`)
**Функции:**
- Создание записей доставки
- Обновление настроек доставки
- Получение постов для разных лент

### FeedService (`lib/services/feed_service.dart`)
**Обновлён для поддержки:**
- `getMainFeed()` - общая лента (как VK "Новости")
- `getSubscriptionsFeed()` - лента подписок
- `getReelsFeed()` - лента рилсов
- Алгоритмическое ранжирование контента

## UI Экран

### CreateCommunityScreen (`lib/features/community/presentation/create_community_screen.dart`)
- Создание сообщества
- Загрузка аватара и обложки
- Выбор тематики
- Настройка ссылок и параметров

### CommunityWallScreen (`lib/features/community/presentation/community_wall_screen.dart`)
- Стена сообщества с двумя разделами:
  - "Все записи" - все посты сообщества
  - "Записи сообщества" - только посты от сообщества
- Закреплённые посты отображаются вверху
- Сортировка по времени

### CreatePostScreen (`lib/features/community/presentation/create_post_screen.dart`)
- Создание постов
- Загрузка фото
- Добавление ссылок
- Автоматическое извлечение тегов

## Логика доставки контента

### При публикации поста:
1. Создаётся запись в `posts`
2. Создаётся запись в `feed_delivery` с флагами:
   - `goesToMainFeed = true`
   - `goesToCommunityWall = true` (если из сообщества)
   - `goesToSubscriptions = true`

### При публикации рилса:
1. Создаётся запись в `reels`
2. Создаётся пост-рилс в `posts` для отображения на стене
3. Создаётся запись в `feed_delivery` с флагами:
   - `goesToMainFeed = true`
   - `goesToReelsFeed = true`
   - `goesToCommunityWall = true`
   - `goesToSubscriptions = true`

## Структура Firestore

```
communities/
  {communityId}/
    - name, avatar, cover, description
    - ownerId, category
    - settings (JSON)
    - membersCount, postsCount

community_members/
  {userId}_{communityId}/
    - userId, communityId
    - role (owner/admin/editor/moderator/member)
    - joinedAt, invitedBy

posts/
  {postId}/
    - authorId, communityId
    - type (text/photo/video/reel/poll/link)
    - content (text, photos, videoUrl, etc.)
    - isPinned, isDeleted
    - createdAt, reactions

reels/
  {reelId}/
    - communityId, authorId
    - urlOriginal, urlTranscoded
    - description, tags
    - views, likes, comments, shares

feed_delivery/
  {deliveryId}/
    - postId, contentType
    - goesToMainFeed
    - goesToReelsFeed
    - goesToCommunityWall
    - goesToSubscriptions
```

## Дополнительные функции (РЕАЛИЗОВАНЫ)

### ✅ Лайки и дизлайки
- **PostInteractionsService** - полная поддержка лайков и дизлайков
- Взаимоисключающие (лайк убирает дизлайк и наоборот)
- Stream-based обновления в реальном времени
- Счётчики в модели PostReactions

### ✅ Комментарии
- **PostCommentsService** - полная система комментариев
- Поддержка ответов на комментарии (вложенные комментарии)
- Лайки комментариев
- Удаление комментариев (мягкое удаление)
- Stream-based обновления

### ✅ Репосты
- **PostInteractionsService.repostPost()** - репост с возможностью добавить текст
- Автоматическая доставка репостов в ленты
- Счётчик репостов в реакциях

### ✅ Сохранения
- **PostInteractionsService.savePost()** - сохранение постов
- Получение списка сохранённых постов
- Stream-based проверка статуса сохранения

### ✅ Статистика
- **StatisticsService** - полная система статистики
- Статистика постов (просмотры, лайки, комментарии, вовлечённость)
- Статистика сообществ (участники, посты, вовлечённость, топ посты)
- Статистика пользователей (посты, лайки, подписчики)
- UI экран статистики сообщества

### ✅ Модерация
- Базовая структура модерации уже есть в проекте
- Жалобы на посты и комментарии
- Мягкое удаление контента

### ✅ Поиск по сообществам
- **CommunityManagementService.searchCommunities()** - поиск по названию

## Использование

### Создание сообщества:
```dart
final community = await CommunityManagementService.createCommunity(
  name: 'Мои рецепты',
  category: 'Рецепты',
  description: 'Делимся рецептами',
  avatarPath: avatarFile.path,
  coverPath: coverFile.path,
);
```

### Публикация поста:
```dart
await PostPublicationService.publishPost(
  communityId: communityId,
  type: PostType.photo,
  text: 'Новый рецепт!',
  photos: photoUrls,
);
```

### Публикация рилса:
```dart
await PostPublicationService.publishReel(
  communityId: communityId,
  videoPath: videoFile.path,
  description: 'Как приготовить...',
);
```

### Получение лент:
```dart
// Общая лента
final mainFeed = await FeedService.getMainFeed();

// Лента подписок
final subscriptionsFeed = await FeedService.getSubscriptionsFeed();

// Лента рилсов
final reelsFeed = await FeedService.getReelsFeed();
```

## Масштабируемость

Архитектура спроектирована для масштабирования:
- Разделение ответственности между сервисами
- Гибкая система доставки контента
- Поддержка различных типов контента
- Система прав и ролей
- Кэширование и оптимизация запросов

