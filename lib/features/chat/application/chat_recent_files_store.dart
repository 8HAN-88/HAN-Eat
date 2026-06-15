import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatRecentFileEntry {
  const ChatRecentFileEntry({
    required this.name,
    required this.sizeBytes,
    required this.sentAt,
    this.mediaUrl,
  });

  final String name;
  final int sizeBytes;
  final DateTime sentAt;
  final String? mediaUrl;

  Map<String, dynamic> toJson() => {
        'name': name,
        'size_bytes': sizeBytes,
        'sent_at': sentAt.toIso8601String(),
        if (mediaUrl != null) 'media_url': mediaUrl,
      };

  factory ChatRecentFileEntry.fromJson(Map<String, dynamic> json) {
    return ChatRecentFileEntry(
      name: json['name'] as String? ?? 'Файл',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      mediaUrl: json['media_url'] as String?,
    );
  }
}

/// Локальный список недавно отправленных файлов (как в Telegram).
class ChatRecentFilesStore {
  ChatRecentFilesStore._();

  static const _prefsKey = 'chat_recent_files_v1';
  static const maxItems = 24;

  static Future<List<ChatRecentFileEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChatRecentFileEntry.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember({
    required String name,
    required int sizeBytes,
    String? mediaUrl,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final items = await load();
    final next = [
      ChatRecentFileEntry(
        name: trimmed,
        sizeBytes: sizeBytes,
        sentAt: DateTime.now(),
        mediaUrl: mediaUrl,
      ),
      ...items.where((e) => e.name != trimmed && e.mediaUrl != mediaUrl),
    ];
    final capped = next.take(maxItems).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
  }
}

String formatChatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
