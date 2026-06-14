import 'package:shared_preferences/shared_preferences.dart';

/// UI-предпочтения экрана «Чаты» (папки, подсказки).
class ChatHubUiPrefs {
  ChatHubUiPrefs._();

  static const _gesturesHintKey = 'chat_hub_gestures_hint_dismissed_v1';
  static const _voiceHintKey = 'chat_voice_hint_dismissed_v1';
  static const _selectedFolderKey = 'chat_selected_folder_id_v1';

  static Future<bool> isVoiceHintDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceHintKey) ?? false;
  }

  static Future<void> dismissVoiceHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceHintKey, true);
  }

  static Future<bool> isGesturesHintDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gesturesHintKey) ?? false;
  }

  static Future<void> dismissGesturesHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gesturesHintKey, true);
  }

  static Future<int?> loadSelectedFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_selectedFolderKey)) return null;
    return prefs.getInt(_selectedFolderKey);
  }

  static Future<void> saveSelectedFolderId(int? folderId) async {
    final prefs = await SharedPreferences.getInstance();
    if (folderId == null) {
      await prefs.remove(_selectedFolderKey);
    } else {
      await prefs.setInt(_selectedFolderKey, folderId);
    }
  }
}
