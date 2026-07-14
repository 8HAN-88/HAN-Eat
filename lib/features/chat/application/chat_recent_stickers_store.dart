import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatRecentStickerEntry {
  const ChatRecentStickerEntry({
    required this.mediaUrl,
    this.emoji,
    this.stickerType,
  });

  final String mediaUrl;
  final String? emoji;
  final String? stickerType;

  Map<String, dynamic> toJson() => {
        'media_url': mediaUrl,
        if (emoji != null && emoji!.trim().isNotEmpty) 'emoji': emoji,
        if (stickerType != null && stickerType!.trim().isNotEmpty)
          'sticker_type': stickerType,
      };

  factory ChatRecentStickerEntry.fromJson(Map<String, dynamic> json) {
    return ChatRecentStickerEntry(
      mediaUrl: json['media_url'] as String? ?? '',
      emoji: json['emoji'] as String?,
      stickerType: json['sticker_type'] as String?,
    );
  }
}

class ChatRecentStickersStore {
  ChatRecentStickersStore._();

  static const _recentKey = 'chat_recent_stickers_v1';
  static const _favoritesKey = 'chat_favorite_stickers_v1';
  static const _maxRecent = 40;

  static Future<List<ChatRecentStickerEntry>> _loadByKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatRecentStickerEntry.fromJson)
          .where((e) => e.mediaUrl.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _saveByKey(
    String key,
    List<ChatRecentStickerEntry> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<List<ChatRecentStickerEntry>> loadRecent() {
    return _loadByKey(_recentKey);
  }

  static Future<List<ChatRecentStickerEntry>> loadFavorites() {
    return _loadByKey(_favoritesKey);
  }

  static Future<void> remember({
    required String mediaUrl,
    String? emoji,
    String? stickerType,
  }) async {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty) return;
    final existing = await loadRecent();
    final next = <ChatRecentStickerEntry>[
      ChatRecentStickerEntry(
        mediaUrl: cleanUrl,
        emoji: emoji,
        stickerType: stickerType,
      ),
      ...existing.where((e) => e.mediaUrl != cleanUrl),
    ];
    await _saveByKey(_recentKey, next.take(_maxRecent).toList());
  }

  static Future<bool> toggleFavorite({
    required String mediaUrl,
    String? emoji,
    String? stickerType,
  }) async {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty) return false;
    final favorites = await loadFavorites();
    final exists = favorites.any((e) => e.mediaUrl == cleanUrl);
    if (exists) {
      await _saveByKey(
        _favoritesKey,
        favorites.where((e) => e.mediaUrl != cleanUrl).toList(),
      );
      return false;
    }
    await _saveByKey(
      _favoritesKey,
      [
        ChatRecentStickerEntry(
          mediaUrl: cleanUrl,
          emoji: emoji,
          stickerType: stickerType,
        ),
        ...favorites,
      ],
    );
    return true;
  }
}
