import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/chat_wallpaper.dart';

/// UI-предпочтения экрана диалога/треда.
class ChatThreadUiPrefs {
  ChatThreadUiPrefs._();

  static const _slowModeCountdownHapticsKey =
      'chat_thread_slow_mode_countdown_haptics_v1';
  static const _autoRetryOnLimitsKey = 'chat_thread_auto_retry_on_limits_v1';
  static const _wallpaperKeyPrefix = 'chat_thread_wallpaper_v1_';

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

  static Future<ChatWallpaperStyle> getWallpaperStyle(int conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    return ChatWallpaperStyle.fromId(prefs.getString(_wallpaperKey(conversationId)));
  }

  static Future<void> setWallpaperStyle(
    int conversationId,
    ChatWallpaperStyle style,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey(conversationId), style.id);
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
