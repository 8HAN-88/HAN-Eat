import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post.dart';
import '../models/post_model.dart';
import '../models/post_types.dart';

/// Сервис для кеширования ленты оффлайн
class FeedCacheService {
  static FeedCacheService? _instance;
  static FeedCacheService get instance {
    if (_instance == null) {
      throw Exception(
        'FeedCacheService not initialized. Call FeedCacheService.init() first.',
      );
    }
    return _instance!;
  }

  static Future<void> init() async {
    if (_instance != null) return;
    _instance = FeedCacheService._internal();
    await _instance!._loadCache();
  }

  static const String _cacheKey = 'feed_cache_v1';
  static const String _cacheTimestampKey = 'feed_cache_timestamp';
  static const String _lastSyncKey = 'feed_last_sync';
  
  final ValueNotifier<List<PostModel>> cachedPosts = ValueNotifier([]);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier(null);
  
  FeedCacheService._internal();

  /// Загрузить кеш из памяти
  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey);
      final lastSync = prefs.getInt(_lastSyncKey);

      if (cacheJson != null && timestamp != null) {
        final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
        final postsJson = cacheData['posts'] as List<dynamic>;
        
        cachedPosts.value = postsJson
            .map((json) => PostModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      if (lastSync != null) {
        lastSyncTime.value = DateTime.fromMillisecondsSinceEpoch(lastSync);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading feed cache: $e');
      cachedPosts.value = [];
    }
  }

  /// Сохранить посты в кеш
  Future<void> cachePosts(List<PostModel> posts, {FeedSortMode? sortMode}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Конвертируем посты в JSON (упрощенная версия без вложенных объектов)
      final postsJson = posts.map((post) => post.toJson()).toList();

      final cacheData = {
        'posts': postsJson,
        'sortMode': sortMode?.name ?? 'personalized',
        'timestamp': now.millisecondsSinceEpoch,
      };

      await prefs.setString(_cacheKey, json.encode(cacheData));
      await prefs.setInt(_cacheTimestampKey, now.millisecondsSinceEpoch);
      await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);

      cachedPosts.value = posts;
      lastSyncTime.value = now;

      if (kDebugMode) {
        debugPrint('Cached ${posts.length} posts at ${now.toIso8601String()}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error caching posts: $e');
    }
  }

  /// Получить кешированные посты
  List<Post> getCachedPosts() {
    // Преобразуем PostModel в Post
    return cachedPosts.value.map((pm) => pm.toPost()).toList();
  }
  
  List<PostModel> getCachedPostModels() {
    return List.from(cachedPosts.value);
  }

  /// Проверить, нужна ли синхронизация
  bool needsSync({Duration? maxAge}) {
    final lastSync = lastSyncTime.value;
    if (lastSync == null) return true;

    final maxAgeDuration = maxAge ?? const Duration(minutes: 5);
    return DateTime.now().difference(lastSync) > maxAgeDuration;
  }

  /// Обновить один пост в кеше (если он есть в сохранённой ленте).
  Future<void> updatePostInCache(Post updatedPost) async {
    await upsertPostModelInCache(PostModel.fromPost(updatedPost));
  }

  /// Подставить свежий [PostModel] вместо существующего с тем же `id`.
  Future<void> upsertPostModelInCache(PostModel pm) async {
    if (cachedPosts.value.isEmpty) return;
    final cached = List<PostModel>.from(cachedPosts.value);
    final idx = cached.indexWhere((p) => p.id == pm.id);
    if (idx < 0) return;
    cached[idx] = pm;
    await cachePosts(cached);
  }

  /// Удалить пост из кеша
  Future<void> removePostFromCache(String postId) async {
    final postIdInt = int.tryParse(postId);
    if (postIdInt == null) return;
    final cached = List<PostModel>.from(cachedPosts.value);
    cached.removeWhere((p) => p.id == postIdInt);
    await cachePosts(cached);
  }

  /// Очистить кеш
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_lastSyncKey);
      
      cachedPosts.value = [];
      lastSyncTime.value = null;
    } catch (e) {
      if (kDebugMode) debugPrint('Error clearing cache: $e');
    }
  }

  /// Получить размер кеша
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) return 0;
      return utf8.encode(cacheJson).length;
    } catch (e) {
      return 0;
    }
  }

  /// Конвертация Post в упрощенный JSON для кеша
  Map<String, dynamic> _postToCache(Post post) {
    return {
      'id': post.id,
      'authorId': post.authorId ?? '',
      'authorName': post.authorName,
      'authorAvatar': post.authorAvatar,
      'groupId': post.groupId,
      'groupName': post.groupName,
      'groupAvatar': post.groupAvatar,
      'type': post.type,
      'status': post.status,
      'text': post.text,
      'photos': post.photos,
      'videoUrl': post.videoUrl,
      'videoThumbnail': post.videoThumbnail,
      'linkUrl': post.linkUrl,
      'linkPreview': post.linkPreview,
      'tags': post.tags,
      'location': post.location,
      'language': post.language,
      'createdAt': post.createdAt.toIso8601String(),
      'reactions': {
        'likes': post.reactions.likes,
        'comments': post.reactions.comments,
        'shares': post.reactions.shares,
        'views': post.reactions.views,
      },
      'isPromoted': post.isPromoted,
      'isAd': post.isAd,
    };
  }

  /// Восстановление Post из кеша (используем PostModel, затем преобразуем)
  Post _postFromCache(Map<String, dynamic> json) {
    // Преобразуем в PostModel формат
    final postModel = PostModel.fromJson(json);
    return postModel.toPost();
  }

  PostType _parsePostType(String? type) {
    return PostType.fromString(type) ?? PostType.text;
  }

  PostStatus _parsePostStatus(String? status) {
    return PostStatus.fromString(status) ?? PostStatus.published;
  }
}


