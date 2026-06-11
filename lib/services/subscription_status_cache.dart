import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_service.dart';

/// Локальный кэш статуса подписки на случай сбоя API.
class SubscriptionStatusCache {
  static const _key = 'subscription_status_cache_v1';

  static Future<void> save(SubscriptionStatusResponse status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(status.toJson()));
  }

  static Future<SubscriptionStatusResponse?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubscriptionStatusResponse.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
