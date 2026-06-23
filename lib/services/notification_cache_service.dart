import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Локальный кэш списка уведомлений для мгновенного открытия экрана.
class NotificationCacheService {
  NotificationCacheService._();

  static const _bodyKey = 'notifications_cache_body_v1';
  static const _savedAtKey = 'notifications_cache_saved_at_v1';

  static Future<NotificationsResponse?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_bodyKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return NotificationsResponse.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveFromResponseBody(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_bodyKey, body);
      await prefs.setInt(
        _savedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bodyKey);
      await prefs.remove(_savedAtKey);
    } catch (_) {}
  }
}
