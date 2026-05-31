import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'channel_service.dart';

/// Кэш на устройстве + синхронизация с API `PATCH /channels/:id/notifications`.
class ChannelNotificationPrefs {
  ChannelNotificationPrefs._();

  static const _prefsKey = 'channel_notifications_enabled_v1';

  static Future<Map<int, bool>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <int, bool>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) result[id] = entry.value == true;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeAll(Map<int, bool> map) async {
    final prefs = await SharedPreferences.getInstance();
    final enc = map.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_prefsKey, jsonEncode(enc));
  }

  /// Обычно из кэша; при открытии экрана лучше вызвать [cacheFromServer] с ответа GET канала.
  static Future<bool> getNotificationsEnabled(int channelId) async {
    final m = await _readAll();
    return m[channelId] ?? true;
  }

  /// Сохранить на сервере и в SharedPreferences.
  static Future<void> setNotificationsEnabled(
    int channelId,
    bool enabled,
  ) async {
    await ChannelService.setChannelNotificationsEnabled(
      channelId: channelId,
      enabled: enabled,
    );
    final m = await _readAll();
    m[channelId] = enabled;
    await _writeAll(m);
  }

  /// Значение из GET `/channels/:id` (`channel_notifications_enabled`).
  static Future<void> cacheFromServer(int channelId, bool enabled) async {
    final m = await _readAll();
    m[channelId] = enabled;
    await _writeAll(m);
  }
}
