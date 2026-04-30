import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../services/push_notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/recipe_model.dart';
import '../models/meal_plan.dart';
import '../models/recipe_category.dart';
import '../models/search_history_entry.dart';

import 'app.dart';
import '../services/favorites_service.dart';
import '../services/shopping_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/notification_settings_service.dart';
import '../services/meal_plan_service.dart';
import '../services/category_service.dart';
import '../services/recipe_service.dart';
import '../services/feed_sync_service.dart';
import '../services/saved_posts_service.dart';

/// Начальная глубокая ссылка (haneat://...) при запуске приложения.
String? initialDeepLink;

Future<void> bootstrap() async {
  // Ensure bindings and any native plugins are ready.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final appLinks = AppLinks();
    final uri = await appLinks.getInitialLink();
    if (uri != null) initialDeepLink = uri.toString();
  } catch (e) {
    debugPrint('getInitialLink error: $e');
  }

  // Shared prefs (если нужны)
  final prefs = await SharedPreferences.getInstance();

  // Инициализируем Hive и сервис избранного
  await Hive.initFlutter();
  
  // Инициализируем форматирование дат для русского языка
  try {
    await initializeDateFormatting('ru', null);
  } catch (e) {
    debugPrint('Date formatting init error (continuing): $e');
  }

  // Register manual adapter if not registered
  if (!Hive.isAdapterRegistered(RecipeModelAdapter().typeId)) {
    Hive.registerAdapter(RecipeModelAdapter());
  }
  
  // Register MealPlan adapters
  if (!Hive.isAdapterRegistered(MealTypeAdapter().typeId)) {
    Hive.registerAdapter(MealTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(MealPlanEntryAdapter().typeId)) {
    Hive.registerAdapter(MealPlanEntryAdapter());
  }
  if (!Hive.isAdapterRegistered(DailyMealPlanAdapter().typeId)) {
    Hive.registerAdapter(DailyMealPlanAdapter());
  }
  
  // Register Category adapters
  if (!Hive.isAdapterRegistered(RecipeCategoryAdapter().typeId)) {
    Hive.registerAdapter(RecipeCategoryAdapter());
  }
  if (!Hive.isAdapterRegistered(CategoryFilterAdapter().typeId)) {
    Hive.registerAdapter(CategoryFilterAdapter());
  }
  
  // Register SearchHistoryEntry adapter
  if (!Hive.isAdapterRegistered(SearchHistoryEntryAdapter().typeId)) {
    Hive.registerAdapter(SearchHistoryEntryAdapter());
  }
  
  // Open Hive boxes
  await Hive.openBox<SearchHistoryEntry>(SearchHistoryEntry.boxName);

  // Load environment variables (create d:\HAN Eat\.env with SPOONACULAR_API_KEY=your_key)
  // Skip on web as .env files are not loaded as assets on web
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      // ignore, continues if no .env provided
      debugPrint('dotenv load error (continuing): $e');
    }
  } else {
    // On web, environment variables should be set via build-time configuration
    // or loaded from a different source (e.g., from backend API)
    debugPrint('Skipping .env load on web platform');
  }

  // Initialize Firebase and Auth (safe: catch & continue)
  bool firebaseInitialized = false;
  try {
    // Check if Firebase is already initialized
    try {
      Firebase.app();
      firebaseInitialized = true;
      debugPrint('✅ Firebase already initialized');
    } catch (_) {
      // Not initialized, try to initialize with firebase_options.dart
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseInitialized = true;
        debugPrint('✅ Firebase initialized successfully');
      } catch (e) {
        // Firebase not configured or error during initialization
        debugPrint('⚠️ Firebase init error (continuing without Firebase): $e');
        firebaseInitialized = false;
      }
    }
  } catch (e) {
    // Firebase not configured (normal for development without Firebase setup)
    debugPrint('⚠️ Firebase init error (continuing without Firebase): $e');
    firebaseInitialized = false;
  }
  
  // Initialize push notifications (only if Firebase is initialized)
  if (firebaseInitialized) {
    try {
      await PushNotificationService.initialize();
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
    }
  }
  
  // Initialize services (they handle Firebase errors gracefully)
  try {
    await AuthService.init();
  } catch (e) {
    debugPrint('AuthService init error: $e');
  }
  
  try {
    await UserService.init();
  } catch (e) {
    debugPrint('UserService init error: $e');
  }

  // Initialize notification settings before NotificationService so _showLocalNotification can consult them.
  try {
    await NotificationSettingsService.init();
  } catch (e) {
    debugPrint('NotificationSettingsService init error: $e');
  }

  // Initialize notifications (requests permissions, registers token, handlers)
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }

  // Initialize favorites/shopping/meal plan/categories etc.
  try {
    await FavoritesService.init();
  } catch (e) {
    debugPrint('FavoritesService init error: $e');
  }
  
  try {
    await ShoppingService.init();
  } catch (e) {
    debugPrint('ShoppingService init error: $e');
  }
  
  try {
    await MealPlanService.init();
  } catch (e) {
    debugPrint('MealPlanService init error: $e');
  }
  
  try {
    await CategoryService.init();
  } catch (e) {
    debugPrint('CategoryService init error: $e');
  }

  // Initialize recipe service (loads cached recipes & starts connectivity monitor)
  try {
    await RecipeService.init();
  } catch (e) {
    debugPrint('RecipeService init error: $e');
  }

  // Initialize feed sync service (offline cache & synchronization)
  try {
    await FeedSyncService.init();
  } catch (e) {
    debugPrint('FeedSyncService init error: $e');
  }

  // Initialize saved posts service (offline cache)
  try {
    await SavedPostsService.init();
  } catch (e) {
    debugPrint('SavedPostsService init error: $e');
  }

  // Minimal warm-up / DI can be added here later.
  runApp(const ProviderScope(child: HanEatApp()));
}
