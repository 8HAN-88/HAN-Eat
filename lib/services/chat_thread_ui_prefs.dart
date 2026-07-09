import 'package:shared_preferences/shared_preferences.dart';

/// UI-предпочтения экрана диалога/треда.
class ChatThreadUiPrefs {
  ChatThreadUiPrefs._();

  static const _slowModeCountdownHapticsKey =
      'chat_thread_slow_mode_countdown_haptics_v1';
  static const _autoRetryOnLimitsKey = 'chat_thread_auto_retry_on_limits_v1';

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
}
