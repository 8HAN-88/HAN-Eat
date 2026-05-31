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
  static const Duration _cacheExpiry = Duration(minutes: 5); // Кэш на 5 минут
  
  // Кэш в памяти для быстрого доступа
  static final Map<int, ChannelDetail> _channelCache = {};
  static final Map<String, List<PostModel>> _postsCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  
  /// Получить канал из кэша или загрузить
  static Future<ChannelDetail> getChannel(int channelId, {bool forceRefresh = false}) async {
    // Проверяем кэш в памяти
    if (!forceRefresh && _channelCache.containsKey(channelId)) {
      final cached = _channelCache[channelId]!;
      final timestamp = _cacheTimestamps['$_channelPrefix$channelId'];
      if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
        return cached;
      }
    }
    
    // Проверяем кэш на диске
    if (!forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_channelPrefix$channelId';
      final timestampKey = '$_cacheTimestampPrefix$channelId';
      
      final cachedJson = prefs.getString(cacheKey);
      final timestampStr = prefs.getString(timestampKey);
      
      if (cachedJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheExpiry) {
          try {
            final data = jsonDecode(cachedJson) as Map<String, dynamic>;
            final channel = ChannelDetail.fromJson(data);
            _channelCache[channelId] = channel;
            return channel;
          } catch (e) {
            debugPrint('Error parsing cached channel: $e');
          }
        }
      }
    }
    
    // Загружаем с сервера
    try {
      final channel = await ChannelService.getChannel(channelId);

      // Сохраняем в кэш
      _channelCache[channelId] = channel;
      _cacheTimestamps['$_channelPrefix$channelId'] = DateTime.now();

      // Сохраняем на диск
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_channelPrefix$channelId', jsonEncode(channel.toJson()));
      await prefs.setString('$_cacheTimestampPrefix$channelId', DateTime.now().toIso8601String());

      return channel;
    } on ChannelNotFoundException {
      await invalidateChannelCache(channelId);
      rethrow;
    }
  }
  
  /// Получить посты из кэша или загрузить
  static Future<List<PostModel>> getChannelPosts({
    required int channelId,
    int limit = 20,
    int offset = 0,
    String? postType,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$_postsPrefix${channelId}_${postType ?? 'all'}_$offset';
    
    // Проверяем кэш в памяти
    if (!forceRefresh && _postsCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _postsCache[cacheKey]!;
      }
    }
    
    // Проверяем кэш на диске
    if (!forceRefresh) {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      final timestampStr = prefs.getString('$_cacheTimestampPrefix$cacheKey');
      
      if (cachedJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheExpiry) {
          try {
            final data = jsonDecode(cachedJson) as List<dynamic>;
            final posts = data.map((p) => PostModel.fromJson(p as Map<String, dynamic>)).toList();
            _postsCache[cacheKey] = posts;
            return posts;
          } catch (e) {
            debugPrint('Error parsing cached posts: $e');
          }
        }
      }
    }
    
    // Загружаем с сервера
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
    
    // Сохраняем в кэш
    _postsCache[cacheKey] = posts;
    _cacheTimestamps[cacheKey] = DateTime.now();
    
    // Сохраняем на диск
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(posts.map((p) => p.toJson()).toList()));
    await prefs.setString('$_cacheTimestampPrefix$cacheKey', DateTime.now().toIso8601String());
    
    return posts;
  }
  
  /// Инвалидировать кэш канала
  static Future<void> invalidateChannelCache(int channelId) async {
    _channelCache.remove(channelId);
    _cacheTimestamps.remove('$_channelPrefix$channelId');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_channelPrefix$channelId');
    await prefs.remove('$_cacheTimestampPrefix$channelId');
    
    // Инвалидируем все посты этого канала
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
  
  /// Очистить весь кэш
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
  
  /// Предзагрузить канал и первые посты
  static Future<void> preloadChannel(int channelId) async {
    try {
      // Загружаем канал и первые посты параллельно
      await Future.wait([
        getChannel(channelId),
        getChannelPosts(channelId: channelId, limit: 20, offset: 0),
      ]);
    } catch (e) {
      debugPrint('Error preloading channel: $e');
    }
  }
}

