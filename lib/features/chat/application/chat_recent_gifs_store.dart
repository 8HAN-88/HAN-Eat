import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatRecentGifEntry {
  const ChatRecentGifEntry({
    required this.mediaUrl,
    required this.sentAt,
  });

  final String mediaUrl;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
        'media_url': mediaUrl,
        'sent_at': sentAt.toIso8601String(),
      };

  factory ChatRecentGifEntry.fromJson(Map<String, dynamic> json) {
    return ChatRecentGifEntry(
      mediaUrl: json['media_url'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Local recent GIFs sent from chat (no Tenor/Giphy).
class ChatRecentGifsStore {
  ChatRecentGifsStore._();

  static const _prefsKey = 'chat_recent_gifs_v1';
  static const maxItems = 36;

  static Future<List<ChatRecentGifEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChatRecentGifEntry.fromJson)
          .where((e) => e.mediaUrl.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember(String mediaUrl) async {
    final url = mediaUrl.trim();
    if (url.isEmpty) return;
    final items = await load();
    final next = [
      ChatRecentGifEntry(mediaUrl: url, sentAt: DateTime.now()),
      ...items.where((e) => e.mediaUrl != url),
    ].take(maxItems).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }
}
