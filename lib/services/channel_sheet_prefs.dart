import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'channel_service.dart';

/// Настройки inbox канала: API + локальный кэш (офлайн).
class ChannelSheetPrefs {
  ChannelSheetPrefs._();

  static const _cacheKey = 'channel_inbox_prefs_cache_v1';
  static Map<int, ChannelInboxPrefs>? _memoryCache;
  static DateTime? _lastSync;

  static Future<Map<int, ChannelInboxPrefs>> _loadCache() async {
    if (_memoryCache != null) return _memoryCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      _memoryCache = {};
      return _memoryCache!;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <int, ChannelInboxPrefs>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key);
        if (id == null || entry.value is! Map) continue;
        out[id] = ChannelInboxPrefs.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      _memoryCache = out;
      return out;
    } catch (_) {
      _memoryCache = {};
      return _memoryCache!;
    }
  }

  static Future<void> _saveCache(Map<int, ChannelInboxPrefs> map) async {
    _memoryCache = map;
    final prefs = await SharedPreferences.getInstance();
    final enc = map.map(
      (k, v) => MapEntry(k.toString(), v.toJson()),
    );
    await prefs.setString(_cacheKey, jsonEncode(enc));
  }

  static Future<void> syncFromServer({bool force = false}) async {
    if (!force &&
        _lastSync != null &&
        DateTime.now().difference(_lastSync!) < const Duration(minutes: 2)) {
      return;
    }
    try {
      final items = await ChannelService.listInboxPrefs();
      final map = {for (final p in items) p.channelId: p};
      await _saveCache(map);
      _lastSync = DateTime.now();
    } catch (_) {}
  }

  static Future<ChannelInboxPrefs> _prefsFor(int channelId) async {
    await syncFromServer();
    final cache = await _loadCache();
    return cache[channelId] ??
        ChannelInboxPrefs(
          channelId: channelId,
          showInFeed: true,
          notificationsEnabled: true,
        );
  }

  static Future<ChannelInboxPrefs?> _patch(
    int channelId, {
    bool? isFavorite,
    bool? inboxArchived,
    bool? showInFeed,
    bool? notificationsEnabled,
  }) async {
    try {
      final updated = await ChannelService.patchInboxPrefs(
        channelId: channelId,
        isFavorite: isFavorite,
        inboxArchived: inboxArchived,
        showInFeed: showInFeed,
        notificationsEnabled: notificationsEnabled,
      );
      final cache = await _loadCache();
      cache[channelId] = updated;
      await _saveCache(cache);
      return updated;
    } catch (_) {
      final cache = await _loadCache();
      final prev = cache[channelId] ??
          ChannelInboxPrefs(
            channelId: channelId,
            showInFeed: true,
            notificationsEnabled: true,
          );
      final next = ChannelInboxPrefs(
        channelId: channelId,
        isFavorite: isFavorite ?? prev.isFavorite,
        inboxArchived: inboxArchived ?? prev.inboxArchived,
        showInFeed: showInFeed ?? prev.showInFeed,
        notificationsEnabled:
            notificationsEnabled ?? prev.notificationsEnabled,
      );
      cache[channelId] = next;
      await _saveCache(cache);
      return next;
    }
  }

  static Future<bool> getShowInFeed(int channelId) async {
    final p = await _prefsFor(channelId);
    return p.showInFeed;
  }

  static Future<void> setShowInFeed(int channelId, bool value) async {
    await _patch(channelId, showInFeed: value);
  }

  static Future<bool> getFavorite(int channelId) async {
    final cache = await _loadCache();
    return cache[channelId]?.isFavorite ?? false;
  }

  static Future<void> setFavorite(int channelId, bool value) async {
    await _patch(channelId, isFavorite: value);
  }

  static Future<Set<int>> listArchivedIds() async {
    await syncFromServer();
    final cache = await _loadCache();
    return cache.entries
        .where((e) => e.value.inboxArchived)
        .map((e) => e.key)
        .toSet();
  }

  static Future<bool> isArchived(int channelId) async {
    final cache = await _loadCache();
    return cache[channelId]?.inboxArchived ?? false;
  }

  static Future<void> setArchived(int channelId, bool archived) async {
    await _patch(channelId, inboxArchived: archived);
  }

  static Future<bool> getNotificationsEnabled(int channelId) async {
    final p = await _prefsFor(channelId);
    return p.notificationsEnabled;
  }

  static Future<void> setNotificationsEnabled(int channelId, bool value) async {
    await _patch(channelId, notificationsEnabled: value);
  }

  static Future<void> seedNotifications(int channelId, bool enabled) async {
    final cache = await _loadCache();
    final prev = cache[channelId] ??
        ChannelInboxPrefs(
          channelId: channelId,
          showInFeed: true,
          notificationsEnabled: true,
        );
    cache[channelId] = ChannelInboxPrefs(
      channelId: channelId,
      isFavorite: prev.isFavorite,
      inboxArchived: prev.inboxArchived,
      showInFeed: prev.showInFeed,
      notificationsEnabled: enabled,
    );
    await _saveCache(cache);
  }

  /// Только для тестов: локальный кэш без сети.
  @visibleForTesting
  static Future<void> seedForTest(Map<int, ChannelInboxPrefs> map) async {
    _lastSync = DateTime.now();
    await _saveCache(map);
  }

  static Future<List<int>> listFavoriteIds() async {
    await syncFromServer();
    final cache = await _loadCache();
    final ids = cache.entries
        .where((e) => e.value.isFavorite)
        .map((e) => e.key)
        .toList()
      ..sort();
    return ids;
  }
}
