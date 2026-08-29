// Кэш-сервис для каналов и постов
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import 'channel_service.dart';

class ChannelCacheService {
  static const String _channelPrefix = 'channel_cache_';
  static const String _postsPrefix = 'channel_posts_cache_';
  static const String _cacheTimestampPrefix = 'channel_cache_timestamp_';
  static const Duration _cacheExpiry = Duration(minutes: 5);

  static final Map<int, ChannelDetail> _channelCache = {};
  static final Map<String, List<PostModel>> _postsCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  static String postsCacheKey({
    required int channelId,
    String? postType,
    int offset = 0,
  }) =>
      '$_postsPrefix${channelId}_${postType ?? 'all'}_$offset';

  static bool _isFresh(DateTime? timestamp) =>
      timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry;

  /// Диск + память, в том числе просроченный кэш (слабая сеть).
  static Future<ChannelDetail?> loadCachedChannel(
    int channelId, {
    bool allowStale = true,
  }) async {
    final memory = _channelCache[channelId];
    final memTs = _cacheTimestamps['$_channelPrefix$channelId'];
    if (memory != null && (allowStale || _isFresh(memTs))) {
      return memory;
    }

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_channelPrefix$channelId';
    final timestampKey = '$_cacheTimestampPrefix$channelId';
    final cachedJson = prefs.getString(cacheKey);
    if (cachedJson == null) return null;
    final timestampStr = prefs.getString(timestampKey);
    final timestamp =
        timestampStr == null ? null : DateTime.tryParse(timestampStr);
    if (!allowStale && !_isFresh(timestamp)) return null;
    try {
      final data = jsonDecode(cachedJson) as Map<String, dynamic>;
      final channel = ChannelDetail.fromJson(data);
      _channelCache[channelId] = channel;
      if (timestamp != null) {
        _cacheTimestamps['$_channelPrefix$channelId'] = timestamp;
      }
      return channel;
    } catch (e) {
      debugPrint('Error parsing cached channel: $e');
      return null;
    }
  }

  static Future<List<PostModel>?> loadCachedPosts({
    required int channelId,
    String? postType,
    int offset = 0,
    bool allowStale = true,
  }) async {
    final cacheKey = postsCacheKey(
      channelId: channelId,
      postType: postType,
      offset: offset,
    );
    final memory = _postsCache[cacheKey];
    final memTs = _cacheTimestamps[cacheKey];
    if (memory != null && (allowStale || _isFresh(memTs))) {
      return List<PostModel>.from(memory);
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(cacheKey);
    if (cachedJson == null) return null;
    final timestampStr = prefs.getString('$_cacheTimestampPrefix$cacheKey');
    final timestamp =
        timestampStr == null ? null : DateTime.tryParse(timestampStr);
    if (!allowStale && !_isFresh(timestamp)) return null;
    try {
      final data = jsonDecode(cachedJson) as List<dynamic>;
      final posts = data
          .map((p) {
            try {
              return PostModel.fromJson(p as Map<String, dynamic>);
            } catch (e) {
              debugPrint('Error parsing cached post: $e');
              return null;
            }
          })
          .whereType<PostModel>()
          .toList();
      _postsCache[cacheKey] = posts;
      if (timestamp != null) _cacheTimestamps[cacheKey] = timestamp;
      return posts;
    } catch (e) {
      debugPrint('Error parsing cached posts: $e');
      return null;
    }
  }

  static Future<void> saveCachedPosts({
    required int channelId,
    required List<PostModel> posts,
    String? postType,
    int offset = 0,
  }) async {
    final cacheKey = postsCacheKey(
      channelId: channelId,
      postType: postType,
      offset: offset,
    );
    _postsCache[cacheKey] = List<PostModel>.from(posts);
    _cacheTimestamps[cacheKey] = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      cacheKey,
      jsonEncode(posts.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      '$_cacheTimestampPrefix$cacheKey',
      DateTime.now().toIso8601String(),
    );
  }

  static Future<void> _saveChannel(ChannelDetail channel) async {
    _channelCache[channel.id] = channel;
    _cacheTimestamps['$_channelPrefix${channel.id}'] = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_channelPrefix${channel.id}',
      jsonEncode(channel.toJson()),
    );
    await prefs.setString(
      '$_cacheTimestampPrefix${channel.id}',
      DateTime.now().toIso8601String(),
    );
  }

  /// Получить канал из кэша или загрузить.
  /// Без [forceRefresh] отдаём даже просроченный кэш — сеть потом.
  static Future<ChannelDetail> getChannel(
    int channelId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await loadCachedChannel(channelId, allowStale: true);
      if (cached != null) return cached;
    }

    try {
      final channel = await ChannelService.getChannel(channelId);
      await _saveChannel(channel);
      return channel;
    } on ChannelNotFoundException {
      await invalidateChannelCache(channelId);
      rethrow;
    } catch (e) {
      final stale = await loadCachedChannel(channelId, allowStale: true);
      if (stale != null) {
        debugPrint('ChannelCacheService: stale channel after error: $e');
        return stale;
      }
      rethrow;
    }
  }

  /// Получить посты из кэша или загрузить.
  static Future<List<PostModel>> getChannelPosts({
    required int channelId,
    int limit = 20,
    int offset = 0,
    String? postType,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await loadCachedPosts(
        channelId: channelId,
        postType: postType,
        offset: offset,
        allowStale: true,
      );
      if (cached != null) return cached;
    }

    try {
      final response = await ChannelService.getChannelPosts(
        channelId: channelId,
        limit: limit,
        offset: offset,
        postType: postType,
      );

      final posts = response.posts.map((p) {
        try {
          return PostModel.fromJson(p);
        } catch (e) {
          debugPrint('Error parsing post: $e');
          return null;
        }
      }).whereType<PostModel>().toList();

      await saveCachedPosts(
        channelId: channelId,
        posts: posts,
        postType: postType,
        offset: offset,
      );
      return posts;
    } catch (e) {
      final stale = await loadCachedPosts(
        channelId: channelId,
        postType: postType,
        offset: offset,
        allowStale: true,
      );
      if (stale != null) {
        debugPrint('ChannelCacheService: stale posts after error: $e');
        return stale;
      }
      rethrow;
    }
  }

  static Future<void> invalidateChannelCache(int channelId) async {
    _channelCache.remove(channelId);
    _cacheTimestamps.remove('$_channelPrefix$channelId');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_channelPrefix$channelId');
    await prefs.remove('$_cacheTimestampPrefix$channelId');

    final keysToRemove = <String>[];
    for (final key in _postsCache.keys) {
      if (key.startsWith('$_postsPrefix$channelId')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _postsCache.remove(key);
      _cacheTimestamps.remove(key);
      await prefs.remove(key);
      await prefs.remove('$_cacheTimestampPrefix$key');
    }
  }

  static Future<void> clearCache() async {
    _channelCache.clear();
    _postsCache.clear();
    _cacheTimestamps.clear();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_channelPrefix) ||
          key.startsWith(_postsPrefix) ||
          key.startsWith(_cacheTimestampPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> preloadChannel(int channelId) async {
    try {
      await Future.wait([
        getChannel(channelId),
        getChannelPosts(channelId: channelId, limit: 20, offset: 0),
      ]);
    } catch (e) {
      debugPrint('Error preloading channel: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _channelCache.clear();
    _postsCache.clear();
    _cacheTimestamps.clear();
  }
}
