import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальные переключатели из bottom sheet канала (пока без отдельного API «избранного канала»).
class ChannelSheetPrefs {
  ChannelSheetPrefs._();

  static const _showInFeedKey = 'channel_sheet_show_in_feed_v1';
  static const _favoriteKey = 'channel_sheet_favorite_v1';
  static const _archivedKey = 'channel_inbox_archived_v1';

  static Future<Map<int, bool>> _readMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
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

  static Future<void> _writeMap(String key, Map<int, bool> map) async {
    final prefs = await SharedPreferences.getInstance();
    final enc = map.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(key, jsonEncode(enc));
  }

  /// Показывать канал в разделе «Каналы» / подборках (локально, по умолчанию true).
  static Future<bool> getShowInFeed(int channelId) async {
    final m = await _readMap(_showInFeedKey);
    return m[channelId] ?? true;
  }

  static Future<void> setShowInFeed(int channelId, bool value) async {
    final m = await _readMap(_showInFeedKey);
    m[channelId] = value;
    await _writeMap(_showInFeedKey, m);
  }

  static Future<bool> getFavorite(int channelId) async {
    final m = await _readMap(_favoriteKey);
    return m[channelId] ?? false;
  }

  static Future<void> setFavorite(int channelId, bool value) async {
    final m = await _readMap(_favoriteKey);
    if (value) {
      m[channelId] = true;
    } else {
      m.remove(channelId);
    }
    await _writeMap(_favoriteKey, m);
  }

  /// Каналы, скрытые из inbox «Чаты» (локально на устройстве).
  static Future<Set<int>> listArchivedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_archivedKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => int.tryParse('$e')).whereType<int>().toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<bool> isArchived(int channelId) async {
    final ids = await listArchivedIds();
    return ids.contains(channelId);
  }

  static Future<void> setArchived(int channelId, bool archived) async {
    final ids = await listArchivedIds();
    if (archived) {
      ids.add(channelId);
    } else {
      ids.remove(channelId);
    }
    final prefs = await SharedPreferences.getInstance();
    final sorted = ids.toList()..sort();
    await prefs.setString(_archivedKey, jsonEncode(sorted));
  }

  /// ID каналов в избранном (порядок по возрастанию id).
  static Future<List<int>> listFavoriteIds() async {
    final m = await _readMap(_favoriteKey);
    final ids = m.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList()
      ..sort();
    return ids;
  }
}
