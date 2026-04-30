# Структура Flutter приложения

## Структура проекта

```
lib/
├── main.dart
├── app.dart                    # Root widget
│
├── core/
│   ├── theme/
│   │   └── app_theme.dart     # Material 3 тема
│   ├── constants/
│   │   └── api_constants.dart  # API URLs, константы
│   └── utils/
│       └── validators.dart     # Валидация форм
│
├── features/
│   ├── auth/
│   │   ├── presentation/
│   │   │   ├── login_screen.dart
│   │   │   └── register_screen.dart
│   │   ├── application/
│   │   │   └── auth_controller.dart
│   │   └── domain/
│   │       └── auth_service.dart
│   │
│   ├── profile/
│   │   ├── presentation/
│   │   │   ├── profile_screen.dart
│   │   │   ├── edit_profile_screen.dart
│   │   │   └── widgets/
│   │   │       ├── profile_header.dart
│   │   │       ├── profile_stats.dart
│   │   │       └── profile_tabs.dart
│   │   ├── application/
│   │   │   └── profile_controller.dart
│   │   └── domain/
│   │       └── profile_service.dart
│   │
│   ├── feed/
│   │   ├── presentation/
│   │   │   ├── home_feed_screen.dart
│   │   │   ├── reels_feed_screen.dart
│   │   │   └── widgets/
│   │   │       ├── feed_item.dart
│   │   │       ├── post_card.dart
│   │   │       └── reel_card.dart
│   │   ├── application/
│   │   │   └── feed_controller.dart
│   │   └── domain/
│   │       └── feed_service.dart
│   │
│   ├── posts/
│   │   ├── presentation/
│   │   │   ├── create_post_screen.dart
│   │   │   ├── create_recipe_screen.dart
│   │   │   ├── post_detail_screen.dart
│   │   │   └── widgets/
│   │   │       ├── post_actions.dart
│   │   │       ├── comments_section.dart
│   │   │       └── recipe_form.dart
│   │   ├── application/
│   │   │   └── post_controller.dart
│   │   └── domain/
│   │       └── post_service.dart
│   │
│   ├── communities/
│   │   ├── presentation/
│   │   │   ├── community_page.dart
│   │   │   ├── create_community_screen.dart
│   │   │   └── widgets/
│   │   │       └── community_header.dart
│   │   ├── application/
│   │   │   └── community_controller.dart
│   │   └── domain/
│   │       └── community_service.dart
│   │
│   └── moderation/            # Для админов
│       └── presentation/
│           └── admin_panel_screen.dart
│
├── shared/
│   ├── models/
│   │   ├── user.dart
│   │   ├── post.dart
│   │   ├── community.dart
│   │   └── comment.dart
│   ├── widgets/
│   │   ├── loading_indicator.dart
│   │   ├── error_widget.dart
│   │   └── image_viewer.dart
│   └── services/
│       ├── api_service.dart
│       ├── storage_service.dart
│       └── notification_service.dart
│
└── routes/
    └── app_router.dart         # Навигация
```

## Основные экраны

### 1. Auth Screens

**Login Screen:**
- Email/Password поля
- Кнопка "Войти"
- Ссылка на регистрацию
- "Забыли пароль?" (опционально)

**Register Screen:**
- Email, Password, Name поля
- Валидация
- Кнопка "Зарегистрироваться"

### 2. Main Navigation

**Bottom Navigation Bar:**
- Home (лента)
- Search (поиск)
- Create (создание поста)
- Notifications (уведомления)
- Profile (профиль)

### 3. Profile Screen

**Компоненты:**
- `ProfileHeader` - аватар, имя, bio, кнопки
- `ProfileStats` - счетчики
- `ProfileTabs` - Posts/Reels/Saved
- `PostsGrid` - сетка постов (3 колонки)
- `ReelsList` - список рилсов
- `SavedList` - сохраненные посты

### 4. Home Feed Screen

**Компоненты:**
- `FeedItem` - карточка поста
- `PostHeader` - автор, время
- `PostMedia` - изображение/видео
- `PostActions` - лайк, комментарий, сохранить
- `PostMetrics` - счетчики
- Infinite scroll

### 5. Create Post Screen

**Шаги:**
1. Выбор типа (Photo/Recipe/Reel/Text)
2. Загрузка медиа
3. Заполнение данных
4. Настройки публикации
5. Публикация

### 6. Post Detail Screen

**Компоненты:**
- Hero image/video
- Заголовок и описание
- Ингредиенты (для рецептов)
- Шаги (для рецептов)
- Комментарии
- Действия (like, save, share)

## State Management

Рекомендуется использовать **Riverpod** или **Provider**:

```dart
// Пример с Riverpod
final feedProvider = StateNotifierProvider<FeedController, FeedState>(
  (ref) => FeedController(ref.read(apiServiceProvider)),
);
```

## API Integration

```dart
// lib/shared/services/api_service.dart
class ApiService {
  static const String baseUrl = 'https://api.haneat.com/api/v1';
  
  Future<List<Post>> getFeed({String? cursor, int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/feed?cursor=$cursor&limit=$limit'),
      headers: await _getHeaders(),
    );
    // Parse and return
  }
  
  Future<Map<String, String>> _getHeaders() async {
    final token = await storageService.getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }
}
```

## Offline Support

Используйте **Hive** или **SQLite** для кэширования:

```dart
// Кэш сохраненных рецептов
class SavedRecipesCache {
  static const String boxName = 'saved_recipes';
  
  Future<void> saveRecipe(Post recipe) async {
    final box = await Hive.openBox(boxName);
    await box.put(recipe.id, recipe.toJson());
  }
  
  Future<List<Post>> getSavedRecipes() async {
    final box = await Hive.openBox(boxName);
    // Return cached recipes
  }
}
```

## Push Notifications

```dart
// lib/shared/services/notification_service.dart
class NotificationService {
  Future<void> initialize() async {
    await FirebaseMessaging.instance.requestPermission();
    
    FirebaseMessaging.instance.onMessage.listen((message) {
      // Handle notification
    });
  }
}
```

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  flutter_riverpod: ^2.4.0
  
  # Networking
  http: ^1.1.0
  dio: ^5.3.0
  
  # Storage
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  shared_preferences: ^2.2.0
  
  # UI
  cached_network_image: ^3.3.0
  video_player: ^2.7.0
  image_picker: ^1.0.0
  
  # Utils
  intl: ^0.18.0
  uuid: ^4.0.0
  
  # Notifications
  firebase_messaging: ^14.7.0
  firebase_core: ^2.24.0
```

## Тестирование

```dart
// test/features/feed/feed_controller_test.dart
void main() {
  test('feed loads posts correctly', () async {
    final controller = FeedController(mockApiService);
    await controller.loadFeed();
    expect(controller.state.posts.length, greaterThan(0));
  });
}
```

