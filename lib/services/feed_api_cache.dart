import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app/app_variant.dart';
import '../models/post_model.dart';

/// Ключи кэша ленты — те же, что рисует UI.
class FeedCacheKeys {
  FeedCacheKeys._();

  static String recommendations({
    String feedType = 'all',
    String sort = 'personalized',
  }) =>
      'rec_${AppVariant.current.name}_${feedType}_$sort';

  static String following({
    String feedType = 'all',
    String sort = 'recent',
  }) =>
      'following_${AppVariant.current.name}_${feedType}_$sort';

  static String reels({bool followingOnly = false}) =>
      followingOnly ? 'rec_reels_following' : 'rec_reels';

  static const legacyRecommendations = 'rec_all_personalized';
  static const legacyFollowing = 'following_all_recent';
}

/// Последняя успешная выдача API `/feed` для офлайн-режима (SharedPreferences).
class FeedApiCache {
  FeedApiCache._();

  static final Map<String, List<PostModel>> _memory = {};

  static final defaultWarmVariants = <String>[
    FeedCacheKeys.recommendations(),
    FeedCacheKeys.legacyRecommendations,
    FeedCacheKeys.following(),
    FeedCacheKeys.legacyFollowing,
    FeedCacheKeys.reels(),
    FeedCacheKeys.reels(followingOnly: true),
  ];

  static List<String> aliasesOf(String variant) {
    if (variant == FeedCacheKeys.recommendations()) {
      return const [FeedCacheKeys.legacyRecommendations, 'rec_all'];
    }
    if (variant == FeedCacheKeys.following()) {
      return const [FeedCacheKeys.legacyFollowing, 'following'];
    }
    return const [];
  }

  static String _prefsKey(String variant) => 'feed_api_cache_v1_$variant';

  /// Синхронно из RAM после [warmUp]. Пустой ключ — смотрим старые алиасы.
  static List<PostModel> peek(String variant) {
    final hit = _memory[variant];
    if (hit != null && hit.isNotEmpty) {
      return List<PostModel>.from(hit);
    }
    for (final alias in aliasesOf(variant)) {
      final other = _memory[alias];
      if (other != null && other.isNotEmpty) {
        return List<PostModel>.from(other);
      }
    }
    return const [];
  }

  /// Прогрев дискового кэша в память до открытия ленты.
  static Future<void> warmUp([List<String>? variants]) async {
    final keys = variants ?? defaultWarmVariants;
    await Future.wait<void>(
      keys.map((variant) async {
        _memory[variant] = await _loadFromDisk(variant);
      }),
    );
  }

  /// Сохранить посты (например `rec_all`, `rec_reels`, `following`).
  static Future<void> save(String variant, List<PostModel> posts) async {
    if (posts.isEmpty) return;
    _memory[variant] = List<PostModel>.from(posts);
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'posts': posts.map((e) => e.toJson()).toList(),
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString(_prefsKey(variant), payload);
    } catch (e) {
      if (kDebugMode) debugPrint('FeedApiCache.save: $e');
    }
  }

  static Future<void> clear(String variant) async {
    _memory.remove(variant);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey(variant));
    } catch (e) {
      if (kDebugMode) debugPrint('FeedApiCache.clear: $e');
    }
  }

  /// Обновить пост во всех закэшированных вариантах ленты.
  static Future<void> patchPost(PostModel pm) async {
    for (final variant in _memory.keys.toList()) {
      final posts = _memory[variant];
      if (posts == null) continue;
      final idx = posts.indexWhere((p) => p.id == pm.id);
      if (idx < 0) continue;
      final next = List<PostModel>.from(posts);
      next[idx] = pm;
      await save(variant, next);
    }
  }

  /// Удалить пост из всех закэшированных вариантов.
  static Future<void> removePost(int postId) async {
    for (final variant in _memory.keys.toList()) {
      final posts = _memory[variant];
      if (posts == null || !posts.any((p) => p.id == postId)) continue;
      final next = posts.where((p) => p.id != postId).toList();
      if (next.isEmpty) {
        await clear(variant);
      } else {
        await save(variant, next);
      }
    }
  }

  /// Поиск поста по id среди прогретых вариантов (для saved_posts и т.п.).
  static PostModel? findPost(int postId) {
    for (final posts in _memory.values) {
      for (final post in posts) {
        if (post.id == postId) return post;
      }
    }
    return null;
  }

  static Future<List<PostModel>> load(String variant) async {
    final memory = _memory[variant];
    if (memory != null && memory.isNotEmpty) {
      return List<PostModel>.from(memory);
    }
    var posts = await _loadFromDisk(variant);
    if (posts.isEmpty) {
      for (final alias in aliasesOf(variant)) {
        final aliased = _memory[alias];
        if (aliased != null && aliased.isNotEmpty) {
          posts = List<PostModel>.from(aliased);
          break;
        }
        posts = await _loadFromDisk(alias);
        if (posts.isNotEmpty) break;
      }
    }
    _memory[variant] = posts;
    return List<PostModel>.from(posts);
  }

  static Future<List<PostModel>> _loadFromDisk(String variant) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(variant));
      if (raw == null || raw.isEmpty) return [];
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['posts'] as List<dynamic>? ?? const [];
      return list
          .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('FeedApiCache.load: $e');
      return [];
    }
  }
}
