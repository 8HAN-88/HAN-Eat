import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/chat_wallpaper.dart';

/// UI-предпочтения экрана диалога/треда.
class ChatThreadUiPrefs {
  ChatThreadUiPrefs._();

  static const _slowModeCountdownHapticsKey =
      'chat_thread_slow_mode_countdown_haptics_v1';
  static const _autoRetryOnLimitsKey = 'chat_thread_auto_retry_on_limits_v1';
  static const _wallpaperKeyPrefix = 'chat_thread_wallpaper_v1_';
  static const _wallpaperCustomPrefix = 'chat_thread_wallpaper_custom_v1_';
  static const _defaultWallpaperKey = 'chat_thread_wallpaper_default_v1';
  static const _defaultWallpaperCustomKey =
      'chat_thread_wallpaper_default_custom_v1';

  static Future<bool> isSlowModeCountdownHapticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_slowModeCountdownHapticsKey) ?? true;
  }

  static Future<void> setSlowModeCountdownHapticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_slowModeCountdownHapticsKey, enabled);
  }

  static Future<bool> isAutoRetryOnLimitsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRetryOnLimitsKey) ?? true;
  }

  static Future<void> setAutoRetryOnLimitsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRetryOnLimitsKey, enabled);
  }

  static String _wallpaperKey(int conversationId) =>
      '$_wallpaperKeyPrefix$conversationId';

  static String _wallpaperCustomKey(int conversationId) =>
      '$_wallpaperCustomPrefix$conversationId';

  static Future<ChatWallpaperStyle> getDefaultWallpaperStyle() async {
    final prefs = await SharedPreferences.getInstance();
    return ChatWallpaperStyle.fromId(prefs.getString(_defaultWallpaperKey));
  }

  static Future<String?> getDefaultCustomWallpaperPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_defaultWallpaperCustomKey)?.trim();
    if (path == null || path.isEmpty) return null;
    return path;
  }

  static Future<void> setDefaultWallpaperStyle(ChatWallpaperStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultWallpaperKey, style.id);
    await prefs.remove(_defaultWallpaperCustomKey);
  }

  static Future<void> setDefaultCustomWallpaperPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultWallpaperCustomKey, path);
    // Keep a style id for fallback if the image is missing.
    if (prefs.getString(_defaultWallpaperKey) == null) {
      await prefs.setString(
        _defaultWallpaperKey,
        ChatWallpaperStyle.defaultStyle.id,
      );
    }
  }

  static Future<ChatWallpaperStyle> getWallpaperStyle(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wallpaperKey(conversationId));
    if (raw != null && raw.isNotEmpty) {
      return ChatWallpaperStyle.fromId(raw);
    }
    return getDefaultWallpaperStyle();
  }

  static Future<String?> getCustomWallpaperPath(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString(_wallpaperCustomKey(conversationId))?.trim();
    if (local != null && local.isNotEmpty) return local;
    // Only fall back to default custom when conversation has no override style.
    if (prefs.containsKey(_wallpaperKey(conversationId)) ||
        prefs.containsKey(_wallpaperCustomKey(conversationId))) {
      return null;
    }
    return getDefaultCustomWallpaperPath();
  }

  static Future<void> setWallpaperStyle(
    int conversationId,
    ChatWallpaperStyle style,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey(conversationId), style.id);
    await prefs.remove(_wallpaperCustomKey(conversationId));
  }

  static Future<void> setCustomWallpaperPath(
    int conversationId,
    String path,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperCustomKey(conversationId), path);
    // Keep last style as soft fallback under the photo.
    if (prefs.getString(_wallpaperKey(conversationId)) == null) {
      await prefs.setString(
        _wallpaperKey(conversationId),
        ChatWallpaperStyle.defaultStyle.id,
      );
    }
  }

  static Future<void> clearConversationWallpaper(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wallpaperKey(conversationId));
    await prefs.remove(_wallpaperCustomKey(conversationId));
  }

  /// Apply style (or custom path) to every conversation that already has a key,
  /// and set as the global default for new chats.
  static Future<void> applyWallpaperToAll({
    ChatWallpaperStyle? style,
    String? customPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (customPath != null && customPath.trim().isNotEmpty) {
      await setDefaultCustomWallpaperPath(customPath.trim());
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith(_wallpaperKeyPrefix))
          .toList();
      for (final key in keys) {
        final idRaw = key.substring(_wallpaperKeyPrefix.length);
        final id = int.tryParse(idRaw);
        if (id == null) continue;
        await prefs.setString(_wallpaperCustomKey(id), customPath.trim());
      }
      return;
    }
    final picked = style ?? ChatWallpaperStyle.defaultStyle;
    await setDefaultWallpaperStyle(picked);
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_wallpaperKeyPrefix))
        .toList();
    for (final key in keys) {
      final idRaw = key.substring(_wallpaperKeyPrefix.length);
      final id = int.tryParse(idRaw);
      if (id == null) continue;
      await prefs.setString(key, picked.id);
      await prefs.remove(_wallpaperCustomKey(id));
    }
  }

  static String _muteUntilKey(int conversationId) =>
      'chat_thread_mute_until_v1_$conversationId';

  static Future<DateTime?> getMuteUntil(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_muteUntilKey(conversationId));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static Future<void> setMuteUntil(
    int conversationId,
    DateTime? until,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _muteUntilKey(conversationId);
    if (until == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, until.toUtc().toIso8601String());
  }
}
