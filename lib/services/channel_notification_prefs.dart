import 'channel_sheet_prefs.dart';

/// @deprecated Используйте [ChannelSheetPrefs]; оставлено для совместимости.
class ChannelNotificationPrefs {
  ChannelNotificationPrefs._();

  static Future<bool> getNotificationsEnabled(int channelId) async {
    return ChannelSheetPrefs.getNotificationsEnabled(channelId);
  }

  static Future<void> setNotificationsEnabled(
    int channelId,
    bool enabled,
  ) async {
    await ChannelSheetPrefs.setNotificationsEnabled(channelId, enabled);
  }

  static Future<void> cacheFromServer(int channelId, bool enabled) async {
    await ChannelSheetPrefs.seedNotifications(channelId, enabled);
  }
}
