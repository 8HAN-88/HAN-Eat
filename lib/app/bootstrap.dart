import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/config/google_auth_config.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../services/push_notification_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/recipe_model.dart';
import '../models/meal_plan.dart';
import '../models/recipe_category.dart';
import '../models/search_history_entry.dart';

import '../services/favorites_service.dart';
import '../services/shopping_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/post_moderation_service.dart';
import '../services/notification_settings_service.dart';
import '../services/meal_plan_service.dart';
import '../services/category_service.dart';
import '../services/recipe_service.dart';
import '../services/feed_sync_service.dart';
import '../services/saved_posts_service.dart';
import '../core/config/app_build_config.dart';
import '../core/config/legacy_firestore_config.dart';
import '../core/crash_reporting.dart';
import '../services/server_config.dart';
import '../services/api_service.dart';

/// Начальная глубокая ссылка (haneat://...) при запуске приложения.
String? initialDeepLink;

/// Лёгкая часть до первого кадра UI ([runHanEatApp] / [StartupShell]).
Future<void> bootstrapEarly() async {
  // Ensure bindings and any native plugins are ready.
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('dotenv load error (continuing): $e');
    }
  }

  debugPrint(
    '📡 HANEAT env=${AppBuildConfig.environment} API ${ServerConfig.apiBaseUrl}',
  );
  if (kReleaseMode && !AppBuildConfig.apiBaseWasConfigured) {
    debugPrint(
      '⚠️ Release без --dart-define=HANEAT_API_BASE — используется ${AppBuildConfig.apiBaseRoot}',
    );
  }
  if (LegacyFirestoreConfig.disabled) {
    debugPrint('Legacy Firestore sync: отключён (release)');
  }
  try {
    final appLinks = AppLinks();
    // На macOS/desktop плагин иногда не отвечает — вечное ожидание блокирует runApp (белый экран).
    final uri = await appLinks
        .getInitialLink()
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    if (uri != null) initialDeepLink = uri.toString();
  } catch (e) {
    debugPrint('getInitialLink error: $e');
  }

  // Shared prefs (если нужны)
  try {
    await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('SharedPreferences at bootstrap: $e');
  }

  // Инициализируем Hive и сервис избранного
  var hiveReady = false;
  try {
    await Hive.initFlutter();
    hiveReady = true;
  } catch (e, st) {
    debugPrint('Hive.initFlutter failed (продолжаем без Hive): $e\n$st');
  }

  if (!hiveReady) {
    debugPrint('⚠️ Пропуск регистрации Hive-адаптеров и локальных боксов');
  } else {
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
  
  // Open Hive boxes (retry: второй экземпляр приложения или быстрый рестарт даёт lock / errno 35)
  Future<void> openSearchHistoryWithRetry() async {
    const maxAttempts = 12;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await Hive.openBox<SearchHistoryEntry>(SearchHistoryEntry.boxName);
        return;
      } catch (e) {
        debugPrint(
          'Hive.openBox(${SearchHistoryEntry.boxName}) attempt ${attempt + 1}/$maxAttempts: $e',
        );
        if (attempt == maxAttempts - 1) {
          // Залипший lock (второй экземпляр, быстрый рестарт). Лучше сбросить локальную
          // историю поиска, чем оставить пользователя с пустым окном (bootstrap не дойдёт до runApp).
          try {
            await Hive.deleteBoxFromDisk(SearchHistoryEntry.boxName);
            await Hive.openBox<SearchHistoryEntry>(SearchHistoryEntry.boxName);
            debugPrint(
              '✅ Hive ${SearchHistoryEntry.boxName}: открыто после deleteBoxFromDisk',
            );
            return;
          } catch (e2) {
            debugPrint('Hive deleteBoxFromDisk recovery failed: $e2');
          }
          debugPrint(
            '⚠️ Hive ${SearchHistoryEntry.boxName}: продолжаем без локальной истории поиска',
          );
          return;
        }
        await Future.delayed(Duration(milliseconds: 80 * (attempt + 1)));
      }
    }
  }

  await openSearchHistoryWithRetry();
  }

  // Инициализируем форматирование дат для русского языка
  try {
    await initializeDateFormatting('ru', null);
  } catch (e) {
    debugPrint('Date formatting init error (continuing): $e');
  }

  // .env уже загружен в начале bootstrapEarly; здесь только лог Google Sign-In.
  if (!kIsWeb) {
    try {
      if (GoogleAuthConfig.isConfigured) {
        debugPrint('Google Sign-In: Web client ID загружен');
        final scheme = GoogleAuthConfig.iosReversedClientId;
        if (scheme != null) {
          debugPrint(
            'Google Sign-In iOS: добавьте в Info.plist CFBundleURLSchemes → $scheme',
          );
        }
      }
    } catch (e) {
      // ignore, continues if no .env provided
      debugPrint('dotenv load error (continuing): $e');
    }
  } else {
    // On web, environment variables should be set via build-time configuration
    // or loaded from a different source (e.g., from backend API)
    debugPrint('Skipping .env load on web platform');
  }
}

/// Firebase, push, локальные сервисы — после первого кадра, чтобы не блокировать
/// merged UI thread на macOS (иначе долгое «пустое» окно).
Future<void> bootstrapServices() async {
  // Initialize Firebase and Auth (safe: catch & continue)
  bool firebaseInitialized = false;
  try {
    // Check if Firebase is already initialized
    try {
      Firebase.app();
      firebaseInitialized = true;
      debugPrint('✅ Firebase already initialized');
      await CrashReporting.initialize(firebaseInitialized: true);
    } catch (_) {
      // Not initialized, try to initialize with firebase_options.dart
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseInitialized = true;
        debugPrint('✅ Firebase initialized successfully');
        await CrashReporting.initialize(firebaseInitialized: true);
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
  
  // Push не должен блокировать вход в приложение (FCM/getToken на desktop могут зависать).
  try {
    await NotificationSettingsService.init();
  } catch (e) {
    debugPrint('NotificationSettingsService init error: $e');
  }

  try {
    await NotificationService.init(
      onPushPayloadTap: PushNotificationService.navigateFromPushData,
    );
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }

  if (firebaseInitialized) {
    unawaited(
      PushNotificationService.initialize()
          .timeout(const Duration(seconds: 12), onTimeout: () {
            debugPrint('PushNotificationService: timeout, продолжаем без push');
          })
          .catchError((Object e) {
            debugPrint('PushNotificationService init error: $e');
          }),
    );
    if (Firebase.apps.isNotEmpty) {
      unawaited(
        PostModerationService.refreshModeratorUidsFromRemote().catchError(
          (Object e) {
            if (kDebugMode) {
              debugPrint('PostModerationService moderator config: $e');
            }
          },
        ),
      );
    }
  }
  
  // Initialize services (they handle Firebase errors gracefully)
  try {
    await AuthService.init();
  } catch (e) {
    debugPrint('AuthService init error: $e');
  }

  AuthService.registerSessionListener((user) {
    if (user != null) {
      unawaited(ApiService.touchAiScanCreditsSilently());
    }
  });
  if (AuthService.instance.currentUser != null) {
    unawaited(ApiService.touchAiScanCreditsSilently());
  }

  if (firebaseInitialized && AuthService.instance.currentUser != null) {
    unawaited(
      PushNotificationService.syncTokenAfterAuth()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () =>
                debugPrint('PushNotificationService.syncTokenAfterAuth: timeout'),
          )
          .catchError((Object e) {
            debugPrint('PushNotificationService.syncTokenAfterAuth: $e');
          }),
    );
  }

  try {
    await UserService.init();
  } catch (e) {
    debugPrint('UserService init error: $e');
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
}
