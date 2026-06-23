import 'package:shared_preferences/shared_preferences.dart';

/// Один раз предложить привязать номер во вкладке «Контакты».
class PhoneLinkPromptStore {
  PhoneLinkPromptStore._();

  static const _contactsPromptKey = 'haneat_contacts_phone_prompt_shown';

  static Future<bool> wasPromptedInContacts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_contactsPromptKey) ?? false;
  }

  static Future<void> markPromptedInContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contactsPromptKey, true);
  }
}
