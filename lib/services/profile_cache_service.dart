import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_service.dart';

/// Кэш профилей для мгновенного открытия экрана.
class ProfileCacheService {
  ProfileCacheService._();

  static final Map<int, Map<String, dynamic>> _memory = {};

  static String _key(int userId) => 'profile_cache_v1_$userId';

  static UserProfile? peek(int userId) {
    final raw = _memory[userId];
    if (raw == null) return null;
    try {
      return UserProfile.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> warmUp(int? userId) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return;
      _memory[userId] = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('ProfileCacheService.warmUp: $e');
    }
  }

  static Future<void> save(int userId, Map<String, dynamic> apiJson) async {
    _memory[userId] = Map<String, dynamic>.from(apiJson);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), jsonEncode(apiJson));
    } catch (e) {
      if (kDebugMode) debugPrint('ProfileCacheService.save: $e');
    }
  }

  static Future<UserProfile?> load(int userId) async {
    final cached = peek(userId);
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _memory[userId] = data;
      return UserProfile.fromJson(data);
    } catch (e) {
      if (kDebugMode) debugPrint('ProfileCacheService.load: $e');
      return null;
    }
  }

  static Future<void> clear(int userId) async {
    _memory.remove(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
