import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/stories/data/story_models.dart';

/// Последние сторис ленты — как Instagram: кольца с диска, пока 3G тянет API.
class StoryFeedCache {
  StoryFeedCache._();

  static const _prefsKey = 'story_feed_cache_v1';
  static List<StoryDto> _memory = const [];

  static List<StoryDto> peek() =>
      List<StoryDto>.from(_memory.where((s) => !s.isExpired));

  static Future<void> warmUp() async {
    _memory = await _loadFromDisk();
  }

  static Future<void> save(List<StoryDto> stories) async {
    final live = stories.where((s) => !s.isExpired).toList();
    _memory = live;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'stories': live.map((e) => e.toJson()).toList(),
          'saved_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('StoryFeedCache.save: $e');
    }
  }

  static Future<List<StoryDto>> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['stories'] as List<dynamic>? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => StoryDto.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => !s.isExpired)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('StoryFeedCache.load: $e');
      return const [];
    }
  }
}
