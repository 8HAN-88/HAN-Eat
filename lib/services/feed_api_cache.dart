import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post_model.dart';

/// Последняя успешная выдача API `/feed` для офлайн-режима (SharedPreferences).
class FeedApiCache {
  FeedApiCache._();

  static String _prefsKey(String variant) => 'feed_api_cache_v1_$variant';

  /// Сохранить посты (например `rec_all`, `rec_reels`, `following`).
  static Future<void> save(String variant, List<PostModel> posts) async {
    if (posts.isEmpty) return;
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

  static Future<List<PostModel>> load(String variant) async {
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
