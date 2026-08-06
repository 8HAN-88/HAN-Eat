import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_models.dart';

/// Кэш сопоставления телефонных хэшей с пользователями HanWe (офлайн, как в Telegram).
class PhoneContactsMatchCache {
  PhoneContactsMatchCache._();

  static const _key = 'haneat_phone_match_cache_v1';
  static const _maxEntries = 2000;

  static Future<Map<String, ChatUserSearchItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, ChatUserSearchItem>{};
      for (final entry in decoded.entries) {
        final hash = entry.key.toString();
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        try {
          out[hash] = ChatUserSearchItem.fromJson(value);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<List<ChatUserSearchItem>> loadForHashes(
    Iterable<String> hashes,
  ) async {
    if (hashes.isEmpty) return [];
    final cache = await loadAll();
    final out = <ChatUserSearchItem>[];
    final seenIds = <int>{};
    for (final hash in hashes) {
      final user = cache[hash];
      if (user == null || seenIds.contains(user.id)) continue;
      seenIds.add(user.id);
      out.add(user);
    }
    return out;
  }

  static Future<void> merge(Iterable<ChatUserSearchItem> users) async {
    final cache = await loadAll();
    for (final user in users) {
      final hash = user.phoneHash;
      if (hash == null || hash.isEmpty) continue;
      cache[hash] = user;
    }
    if (cache.length > _maxEntries) {
      final keys = cache.keys.toList()..sort();
      while (cache.length > _maxEntries && keys.isNotEmpty) {
        cache.remove(keys.removeAt(0));
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        for (final e in cache.entries) e.key: e.value.toJson(),
      }),
    );
  }
}
