import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post_model.dart';

/// Кэш постов на стене профиля (первая страница).
class UserPostsCacheService {
  UserPostsCacheService._();

  static final Map<String, List<PostModel>> _memory = {};

  static String _variant(int userId, String? postType) =>
      '${userId}_${postType ?? 'all'}';

  static String _key(String variant) => 'user_posts_cache_v1_$variant';

  static List<PostModel>? peek(int userId, {String? postType}) {
    final posts = _memory[_variant(userId, postType)];
    if (posts == null || posts.isEmpty) return null;
    return List<PostModel>.from(posts);
  }

  static Future<void> save(
    int userId, {
    String? postType,
    required List<PostModel> posts,
  }) async {
    if (posts.isEmpty) return;
    final variant = _variant(userId, postType);
    _memory[variant] = List<PostModel>.from(posts);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(variant),
        jsonEncode({
          'posts': posts.map((p) => p.toJson()).toList(),
          'saved_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('UserPostsCacheService.save: $e');
    }
  }

  static Future<List<PostModel>> load(int userId, {String? postType}) async {
    final cached = peek(userId, postType: postType);
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(_variant(userId, postType)));
      if (raw == null || raw.isEmpty) return [];
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['posts'] as List<dynamic>? ?? const [];
      final posts = list
          .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _memory[_variant(userId, postType)] = posts;
      return posts;
    } catch (e) {
      if (kDebugMode) debugPrint('UserPostsCacheService.load: $e');
      return [];
    }
  }
}
