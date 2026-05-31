import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/post_types.dart';
import 'api_service.dart';
import 'feed_service.dart';
import 'feed_cache_service.dart';

/// Сервис синхронизации ленты (онлайн/оффлайн)
class FeedSyncService {
  static FeedSyncService? _instance;
  static FeedSyncService get instance {
    if (_instance == null) {
      throw Exception(
        'FeedSyncService not initialized. Call FeedSyncService.init() first.',
      );
    }
    return _instance!;
  }

  static Future<void> init() async {
    if (_instance != null) return;
    await FeedCacheService.init();
    _instance = FeedSyncService._internal();
    _instance!._initConnectivity();
  }

  FeedSyncService._internal();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier(true);

  void _initConnectivity() {
    _connectivity.onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      isOnline.value = online;
      
      if (kDebugMode) {
        debugPrint('Connectivity changed: ${online ? "online" : "offline"}');
      }

      // При появлении интернета - автоматическая синхронизация
      if (online) {
        syncFeedInBackground();
      }
    });

    // Проверяем текущее состояние
    _connectivity.checkConnectivity().then((result) {
      isOnline.value = !result.contains(ConnectivityResult.none);
    });
  }

  /// Синхронизировать ленту с сервером
  Future<List<Post>> syncFeed({
    FeedSortMode sortMode = FeedSortMode.personalized,
    bool force = false,
  }) async {
    // Проверяем, нужна ли синхронизация
    if (!force && !FeedCacheService.instance.needsSync()) {
      if (kDebugMode) debugPrint('Cache is fresh, using cached feed');
      return FeedCacheService.instance.getCachedPosts();
    }

    // Если оффлайн - возвращаем кеш
    if (!isOnline.value) {
      if (kDebugMode) debugPrint('Offline mode, using cached feed');
      return FeedCacheService.instance.getCachedPosts();
    }

    try {
      // Загружаем свежие посты
      final postModels = await FeedService.getMainFeed(
        mode: sortMode,
        limit: 50,
      );

      // Преобразуем PostModel в Post
      final posts = postModels.map((pm) => pm.toPost()).toList();

      // Сохраняем в кеш (используем PostModel для кеша)
      await FeedCacheService.instance.cachePosts(postModels, sortMode: sortMode);

      if (kDebugMode) {
        debugPrint('Synced ${posts.length} posts from server');
      }

      return posts;
    } catch (e) {
      if (kDebugMode) debugPrint('Error syncing feed: $e');
      
      // При ошибке возвращаем кеш
      final cached = FeedCacheService.instance.getCachedPosts();
      if (cached.isNotEmpty) {
        if (kDebugMode) debugPrint('Using cached feed as fallback');
        return cached;
      }
      
      rethrow;
    }
  }

  /// Синхронизация в фоновом режиме (без блокировки UI)
  Future<void> syncFeedInBackground({
    FeedSortMode sortMode = FeedSortMode.personalized,
  }) async {
    if (!isOnline.value) return;

    try {
      final posts = await FeedService.getMainFeed(
        mode: sortMode,
        limit: 50,
      );

      await FeedCacheService.instance.cachePosts(posts, sortMode: sortMode);

      if (kDebugMode) {
        debugPrint('Background sync completed: ${posts.length} posts');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Background sync failed: $e');
    }
  }

  /// Подтянуть один пост с API и обновить его в оффлайн-кеше ленты.
  Future<void> syncPost(String postId) async {
    if (!isOnline.value) return;
    final id = int.tryParse(postId);
    if (id == null) return;

    try {
      final pm = await ApiService.getPostById(id);
      if (pm == null) return;
      await FeedCacheService.instance.upsertPostModelInCache(pm);
      if (kDebugMode) debugPrint('Synced post $postId in feed cache');
    } catch (e) {
      if (kDebugMode) debugPrint('Error syncing post: $e');
    }
  }

  /// Получить ленту (с автоматической синхронизацией)
  Future<List<Post>> getFeed({
    FeedSortMode sortMode = FeedSortMode.personalized,
    bool useCache = true,
  }) async {
    // Если запрошен только кеш
    if (useCache && !FeedCacheService.instance.needsSync()) {
      return FeedCacheService.instance.getCachedPosts();
    }

    // Пытаемся синхронизировать
    return await syncFeed(sortMode: sortMode, force: !useCache);
  }

  /// Очистить кеш и синхронизировать заново
  Future<List<Post>> refreshFeed({
    FeedSortMode sortMode = FeedSortMode.personalized,
  }) async {
    await FeedCacheService.instance.clearCache();
    return await syncFeed(sortMode: sortMode, force: true);
  }
}

