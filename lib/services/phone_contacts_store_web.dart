import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WebPhoneBookEntry {
  const WebPhoneBookEntry({
    required this.displayName,
    required this.phoneE164,
  });

  final String displayName;
  final String phoneE164;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'phoneE164': phoneE164,
      };

  factory WebPhoneBookEntry.fromJson(Map<String, dynamic> json) {
    return WebPhoneBookEntry(
      displayName: (json['displayName'] as String? ?? '').trim(),
      phoneE164: (json['phoneE164'] as String? ?? '').trim(),
    );
  }
}

/// Локальная телефонная книга в браузере (Contact Picker + ручной ввод).
class WebPhoneContactsStore {
  WebPhoneContactsStore._();

  static const _key = 'haneat_web_phone_contacts_v1';

  static Future<List<WebPhoneBookEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WebPhoneBookEntry.fromJson)
          .where((e) => e.phoneE164.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<WebPhoneBookEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = entries.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(payload));
  }

  static Future<List<WebPhoneBookEntry>> merge(
    Iterable<WebPhoneBookEntry> incoming,
  ) async {
    final existing = await load();
    final byPhone = <String, WebPhoneBookEntry>{
      for (final e in existing) e.phoneE164: e,
    };
    for (final e in incoming) {
      if (e.phoneE164.isEmpty) continue;
      final prev = byPhone[e.phoneE164];
      if (prev == null || e.displayName.isNotEmpty) {
        byPhone[e.phoneE164] = e;
      }
    }
    final merged = byPhone.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    await save(merged);
    return merged;
  }
}
