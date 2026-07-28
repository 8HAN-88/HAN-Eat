import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/sticker_service.dart';

class ChatStickerPinnedPacksStore {
  ChatStickerPinnedPacksStore._();

  static const _prefsKey = 'chat_sticker_pinned_packs_v1';
  static const _migratedKey = 'chat_sticker_pinned_packs_cloud_migrated_v1';

  static Future<List<int>> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => e is num ? e.toInt() : -1)
          .where((e) => e > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveLocal(List<int> ids) async {
    final unique = <int>[];
    final seen = <int>{};
    for (final id in ids) {
      if (id <= 0 || !seen.add(id)) continue;
      unique.add(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(unique));
  }

  /// Offline cache first, then cloud sync (migrates local pins once).
  static Future<List<int>> load() async {
    final local = await loadLocal();
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrated = prefs.getBool(_migratedKey) ?? false;
      var cloud = await StickerService.listPinnedPacks();
      if (!migrated && local.isNotEmpty && cloud.isEmpty) {
        cloud = await StickerService.replacePinnedPacks(local);
      }
      await prefs.setBool(_migratedKey, true);
      await saveLocal(cloud);
      return cloud;
    } catch (_) {
      return local;
    }
  }

  static Future<void> save(List<int> ids) async {
    await saveLocal(ids);
    try {
      final cloud = await StickerService.replacePinnedPacks(ids);
      await saveLocal(cloud);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migratedKey, true);
    } catch (_) {
      // Keep local order; next load will retry sync.
    }
  }

  static Future<bool> toggle(int packId) async {
    final current = await loadLocal();
    final willPin = !current.contains(packId);
    final optimistic = willPin
        ? [packId, ...current.where((e) => e != packId)]
        : current.where((e) => e != packId).toList();
    await saveLocal(optimistic);
    try {
      final result = await StickerService.togglePinnedPack(packId);
      await saveLocal(result.packIds);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_migratedKey, true);
      return result.pinned;
    } catch (_) {
      return willPin;
    }
  }
}
