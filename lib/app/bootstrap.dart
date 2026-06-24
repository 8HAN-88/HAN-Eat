import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/config/google_auth_config.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../services/push_notification_service.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import '../services/feed_cache_service.dart';
import '../services/feed_api_cache.dart';
import '../services/saved_posts_service.dart';
import '../services/chat_cache_service.dart';
import '../services/profile_cache_service.dart';
import '../services/menu_recommendations_cache.dart';
import '../services/menu_search_cache.dart';
import '../services/global_search_cache.dart';
import '../services/subscription_status_cache.dart';
import '../services/api_reachability_service.dart';
import '../services/history_storage.dart';
import '../core/config/app_build_config.dart';
import '../core/config/legacy_firestore_config.dart';
import '../core/crash_reporting.dart';
import '../services/server_config.dart';
import '../services/api_service.dart';
import '../services/user_realtime_service.dart';
import '../core/network/api_endpoint_resolver.dart';
import '../core/network/haneat_http_client.dart';
import '../core/storage/hive_bootstrap.dart';
import 'app_bootstrap_state.dart';

/// Начальная глубокая ссылка (haneat://...) при запуске приложения.
String? initialDeepLink;

/// Лёгкая часть до первого кадра UI ([runHanEatApp] / [StartupShell]).
Future<void> bootstrapEarly() async {
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('dotenv load error (continuing): $e');
    }
    await ApiEndpointResolver.resolve().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('⚠️ ApiEndpointResolver: timeout 3s — продолжаем с конфигом по умолчанию');
      },
    );
  }

  debugPrint(
    '📡 HANEAT env=${AppBuildConfig.environment} API ${ServerConfig.apiBaseUrl}'
    '${ApiEndpointResolver.usingIpFallback ? ' (IP fallback)' : ''}',
  );
  if (kReleaseMode && !AppBuildConfig.apiBaseWasConfigured) {
    debugPrint(
      '⚠️ Release без --dart-define=HANEAT_API_BASE — используется ${AppBuildConfig.apiBaseRoot}',
    );
  }
  if (LegacyFirestoreConfig.disabled) {
    debugPrint('Legacy Firestore sync: отключён (release)');
  }
  final linkTimeout = (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android))
      ? const Duration(milliseconds: 600)
      : const Duration(seconds: 2);

  unawaited(() async {
    try {
      final uri = await AppLinks()
          .getInitialLink()
          .timeout(linkTimeout, onTimeout: () => null);
      if (uri != null) initialDeepLink = uri.toString();
    } catch (e) {
      debugPrint('getInitialLink error: $e');
    }
  }());
  unawaited(() async {
    try {
      await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences at bootstrap: $e');
    }
  }());

  // Форматирование дат и шрифты — в [bootstrapServicesDeferred], не блокируем runApp.

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

/// Минимум в фоне: сессия из кэша (без Firebase — он в deferred).
Future<void> bootstrapServicesForFirstFrame() async {
  try {
    await AuthService.init(deferTokenRefresh: true);
  } catch (e) {
    debugPrint('AuthService init error (сессия из кэша сохранена): $e');
  }

  unawaited(
    Future.wait<void>([
      FeedCacheService.init().catchError((Object e) {
        debugPrint('FeedCacheService early init: $e');
      }),
      FeedApiCache.warmUp().catchError((Object e) {
        debugPrint('FeedApiCache warmUp: $e');
      }),
      ChatCacheService.warmUp().catchError((Object e) {
        debugPrint('ChatCacheService warmUp: $e');
      }),
      ProfileCacheService.warmUp(AuthService.instance.currentUser?.id)
          .catchError((Object e) {
        debugPrint('ProfileCacheService warmUp: $e');
      }),
      MenuRecommendationsCache.warmUp().catchError((Object e) {
        debugPrint('MenuRecommendationsCache warmUp: $e');
      }),
      MenuSearchCache.warmUp().catchError((Object e) {
        debugPrint('MenuSearchCache warmUp: $e');
      }),
      GlobalSearchCache.warmUp().catchError((Object e) {
        debugPrint('GlobalSearchCache warmUp: $e');
      }),
      SubscriptionStatusCache.warmUp().catchError((Object e) {
        debugPrint('SubscriptionStatusCache warmUp: $e');
      }),
    ]),
  );

  // Прогрев API — параллельно с первым кадром, не блокируем UI.
  unawaited(
    Future.wait<void>([
      ApiReachabilityService.init().catchError((Object e) {
        debugPrint('ApiReachabilityService early init: $e');
      }),
      _warmApiConnection().catchError((Object e) {
        debugPrint('API warm-up early: $e');
      }),
    ]),
  );
}

bool _firebaseReady = false;

Future<bool> ensureFirebaseReady() => _initFirebase();

Future<bool> _initFirebase() async {
  if (_firebaseReady) return true;
  try {
    try {
      Firebase.app();
      _firebaseReady = true;
      debugPrint('✅ Firebase already initialized');
      return true;
    } catch (_) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code != 'duplicate-app') rethrow;
        debugPrint('Firebase: duplicate-app (native configure), using default app');
      }
      _firebaseReady = true;
      debugPrint('✅ Firebase initialized successfully');
      return true;
    }
  } catch (e) {
    debugPrint('⚠️ Firebase init error (continuing without Firebase): $e');
    return false;
  }
}

/// Прогрев TLS/TCP к API (не блокирует UI).
Future<void> _warmApiConnection() async {
  try {
    HanEatHttpClient.ensureHealthy();
    final uri = Uri.parse('${ServerConfig.baseUrl}/health');
    await HanEatHttpClient.withShared(
      (client) => client.get(uri).timeout(
        kIsWeb ? const Duration(seconds: 6) : const Duration(seconds: 8),
      ),
    );
    if (kDebugMode) debugPrint('API warm-up: OK');
  } catch (e) {
    if (kDebugMode) debugPrint('API warm-up: $e');
  }
}

/// Остальные сервисы — в фоне после показа UI.
Future<void> bootstrapServicesDeferred() async {
  unawaited(
    ApiReachabilityService.init().catchError((Object e) {
      debugPrint('ApiReachabilityService deferred init: $e');
    }),
  );

  if (kIsWeb) {
    AppBootstrapState.hiveReady.value = true;
    unawaited(
      ensureHiveReady().timeout(const Duration(seconds: 8)).catchError((Object e) {
        debugPrint('bootstrapServicesDeferred ensureHiveReady (web): $e');
      }),
    );
  } else {
    try {
      await ensureHiveReady().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('⚠️ deferred ensureHiveReady: timeout 8s');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapServicesDeferred ensureHiveReady: $e\n$st');
    } finally {
      AppBootstrapState.hiveReady.value = true;
    }
  }

  unawaited(_warmApiConnection());

  final firebaseInitialized =
      kIsWeb ? false : await ensureFirebaseReady();
  if (kIsWeb) {
    unawaited(
      ensureFirebaseReady().catchError((Object e) {
        debugPrint('Firebase init (web deferred): $e');
        return false;
      }),
    );
  }

  unawaited(() async {
    try {
      await initializeDateFormatting('ru', null);
    } catch (e) {
      debugPrint('Date formatting init error: $e');
    }
    // Manrope в assets/fonts — сеть не нужна.
  }());

  unawaited(
    HistoryStorage.ensureOpen().catchError((Object e) {
      debugPrint('HistoryStorage.ensureOpen: $e');
    }),
  );

  if (firebaseInitialized) {
    try {
      await NotificationSettingsService.init();
    } catch (e) {
      debugPrint('NotificationSettingsService init error: $e');
    }
  }

  final localNotifDelay = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      ? const Duration(seconds: 4)
      : Duration.zero;
  if (!kIsWeb) {
    Future<void>.delayed(localNotifDelay, () {
      unawaited(
        NotificationService.init(
          onPushPayloadTap: PushNotificationService.navigateFromPushData,
        ).catchError((Object e) {
          debugPrint('NotificationService init error: $e');
        }),
      );
    });
  }

  if (firebaseInitialized && !kIsWeb) {
    final pushDelay = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? const Duration(seconds: 12)
        : const Duration(seconds: 2);
    Future<void>.delayed(pushDelay, () {
      unawaited(
        PushNotificationService.initialize()
            .timeout(const Duration(seconds: 12), onTimeout: () {
              debugPrint('PushNotificationService: timeout');
            })
            .catchError((Object e) {
              debugPrint('PushNotificationService init error: $e');
            }),
      );
    });
    if (Firebase.apps.isNotEmpty && LegacyFirestoreConfig.enabled) {
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

  Future<void> safeInit(Future<void> f, String name) async {
    try {
      await f;
    } catch (e) {
      debugPrint('bootstrapServicesDeferred $name: $e');
    }
  }

  final criticalInits = <Future<void>>[
    safeInit(UserService.init(), 'UserService'),
    safeInit(FeedSyncService.init(), 'FeedSyncService'),
    safeInit(SavedPostsService.init(), 'SavedPostsService'),
    safeInit(UserRealtimeService.init(), 'UserRealtimeService'),
  ];
  if (!kIsWeb) {
    criticalInits.addAll([
      safeInit(FavoritesService.init(), 'FavoritesService'),
      safeInit(ShoppingService.init(), 'ShoppingService'),
      safeInit(MealPlanService.init(), 'MealPlanService'),
      safeInit(CategoryService.init(), 'CategoryService'),
      safeInit(RecipeService.init(), 'RecipeService'),
    ]);
  }
  await Future.wait<void>(criticalInits, eagerError: false);

  if (kIsWeb) {
    unawaited(
      Future.wait<void>([
        safeInit(FavoritesService.init(), 'FavoritesService'),
        safeInit(ShoppingService.init(), 'ShoppingService'),
        safeInit(MealPlanService.init(), 'MealPlanService'),
        safeInit(CategoryService.init(), 'CategoryService'),
        safeInit(RecipeService.init(), 'RecipeService'),
      ], eagerError: false),
    );
  }
  if (AuthService.instance.currentUser != null) {
    unawaited(
      SavedPostsService.processPendingOps().catchError((Object e) {
        debugPrint('SavedPostsService.processPendingOps: $e');
      }),
    );
    unawaited(
      SavedPostsService.syncWithServer().catchError((Object e) {
        debugPrint('SavedPostsService.syncWithServer: $e');
        return const SavedSyncResult(success: false);
      }),
    );
  }
  if (firebaseInitialized && !kIsWeb) {
    Future<void>.delayed(const Duration(seconds: 5), () {
      unawaited(
        CrashReporting.initialize(firebaseInitialized: true).catchError((Object e) {
          debugPrint('CrashReporting init error: $e');
        }),
      );
    });
  }

  if (kDebugMode) debugPrint('✅ bootstrapServicesDeferred завершён');
}

/// Полная инициализация (тесты, старые вызовы).
Future<void> bootstrapServices() async {
  await bootstrapServicesForFirstFrame();
  await bootstrapServicesDeferred();
}
