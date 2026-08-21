import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/sticker_service.dart';

class ChatRecentStickerEntry {
  const ChatRecentStickerEntry({
    required this.mediaUrl,
    this.emoji,
    this.stickerType,
    this.stickerId,
  });

  final String mediaUrl;
  final String? emoji;
  final String? stickerType;
  final int? stickerId;

  Map<String, dynamic> toJson() => {
        'media_url': mediaUrl,
        if (emoji != null && emoji!.trim().isNotEmpty) 'emoji': emoji,
        if (stickerType != null && stickerType!.trim().isNotEmpty)
          'sticker_type': stickerType,
        if (stickerId != null && stickerId! > 0) 'sticker_id': stickerId,
      };

  factory ChatRecentStickerEntry.fromJson(Map<String, dynamic> json) {
    return ChatRecentStickerEntry(
      mediaUrl: json['media_url'] as String? ?? '',
      emoji: json['emoji'] as String?,
      stickerType: json['sticker_type'] as String?,
      stickerId: (json['sticker_id'] as num?)?.toInt(),
    );
  }
}

class ChatRecentStickersStore {
  ChatRecentStickersStore._();

  static const _recentKey = 'chat_recent_stickers_v1';
  static const _favoritesKey = 'chat_favorite_stickers_v1';
  static const _favoritesMigratedKey = 'chat_favorite_stickers_cloud_migrated_v1';
  static const _maxRecent = 40;

  static Future<List<ChatRecentStickerEntry>> _loadByKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((e) => ChatRecentStickerEntry.fromJson(
                Map<String, dynamic>.from(e),
              ))
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

  static Future<List<ChatRecentStickerEntry>> loadFavoritesLocal() {
    return _loadByKey(_favoritesKey);
  }

  /// Offline cache first, then cloud sync (migrates local URL favorites once).
  static Future<List<ChatRecentStickerEntry>> loadFavorites() async {
    final local = await loadFavoritesLocal();
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrated = prefs.getBool(_favoritesMigratedKey) ?? false;
      var cloud = await StickerService.listFavorites();
      if (!migrated && local.isNotEmpty && cloud.isEmpty) {
        cloud = await StickerService.replaceFavorites(
          stickerIds: [
            for (final e in local)
              if (e.stickerId != null && e.stickerId! > 0) e.stickerId!,
          ],
          mediaUrls: [
            for (final e in local)
              if (e.stickerId == null || e.stickerId! <= 0) e.mediaUrl,
          ],
        );
      }
      await prefs.setBool(_favoritesMigratedKey, true);
      final mapped = [
        for (final item in cloud)
          ChatRecentStickerEntry(
            mediaUrl: item.mediaUrl,
            emoji: item.emoji,
            stickerType: item.stickerType,
            stickerId: item.id,
          ),
      ];
      await _saveByKey(_favoritesKey, mapped);
      return mapped;
    } catch (_) {
      return local;
    }
  }

  static Future<void> remember({
    required String mediaUrl,
    String? emoji,
    String? stickerType,
    int? stickerId,
  }) async {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty) return;
    final existing = await loadRecent();
    final next = <ChatRecentStickerEntry>[
      ChatRecentStickerEntry(
        mediaUrl: cleanUrl,
        emoji: emoji,
        stickerType: stickerType,
        stickerId: stickerId,
      ),
      ...existing.where((e) => e.mediaUrl != cleanUrl),
    ];
    await _saveByKey(_recentKey, next.take(_maxRecent).toList());
  }

  static Future<bool> toggleFavorite({
    required String mediaUrl,
    String? emoji,
    String? stickerType,
    int? stickerId,
  }) async {
    final cleanUrl = mediaUrl.trim();
    if (cleanUrl.isEmpty) return false;

    // Optimistic local update for snappy UI / offline.
    final favorites = await loadFavoritesLocal();
    final exists = favorites.any(
      (e) =>
          e.mediaUrl == cleanUrl ||
          (stickerId != null &&
              stickerId > 0 &&
              e.stickerId != null &&
              e.stickerId == stickerId),
    );
    if (exists) {
      await _saveByKey(
        _favoritesKey,
        favorites
            .where(
              (e) =>
                  e.mediaUrl != cleanUrl &&
                  !(stickerId != null &&
                      stickerId > 0 &&
                      e.stickerId == stickerId),
            )
            .toList(),
      );
    } else {
      await _saveByKey(
        _favoritesKey,
        [
          ChatRecentStickerEntry(
            mediaUrl: cleanUrl,
            emoji: emoji,
            stickerType: stickerType,
            stickerId: stickerId,
          ),
          ...favorites,
        ],
      );
    }

    try {
      final favorited = await StickerService.toggleFavorite(
        stickerId: stickerId,
        mediaUrl: cleanUrl,
      );
      final cloud = await StickerService.listFavorites();
      final mapped = [
        for (final item in cloud)
          ChatRecentStickerEntry(
            mediaUrl: item.mediaUrl,
            emoji: item.emoji,
            stickerType: item.stickerType,
            stickerId: item.id,
          ),
      ];
      await _saveByKey(_favoritesKey, mapped);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_favoritesMigratedKey, true);
      return favorited;
    } catch (e) {
      await _saveByKey(_favoritesKey, favorites);
      rethrow;
    }
  }
}
