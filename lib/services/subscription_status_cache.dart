import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_service.dart';

/// Локальный кэш статуса подписки на случай сбоя API.
class SubscriptionStatusCache {
  static const _key = 'subscription_status_cache_v1';

  static SubscriptionStatusResponse? _memory;

  static SubscriptionStatusResponse? peek() => _memory;

  static Future<void> warmUp() async {
    if (_memory != null) return;
    _memory = await load();
  }

  static Future<void> save(SubscriptionStatusResponse status) async {
    _memory = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(status.toJson()));
  }

  static Future<SubscriptionStatusResponse?> load() async {
    if (_memory != null) return _memory;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _memory = SubscriptionStatusResponse.fromJson(map);
      return _memory;
    } catch (e) {
      if (kDebugMode) debugPrint('SubscriptionStatusCache.load: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    _memory = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
