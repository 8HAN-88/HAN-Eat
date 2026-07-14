import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatStickerPinnedPacksStore {
  ChatStickerPinnedPacksStore._();

  static const _prefsKey = 'chat_sticker_pinned_packs_v1';

  static Future<List<int>> load() async {
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

  static Future<void> save(List<int> ids) async {
    final unique = <int>[];
    final seen = <int>{};
    for (final id in ids) {
      if (id <= 0 || !seen.add(id)) continue;
      unique.add(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(unique));
  }

  static Future<bool> toggle(int packId) async {
    final current = await load();
    if (current.contains(packId)) {
      await save(current.where((e) => e != packId).toList());
      return false;
    }
    await save([packId, ...current]);
    return true;
  }
}
