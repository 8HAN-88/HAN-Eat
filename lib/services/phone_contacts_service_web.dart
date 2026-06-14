import 'phone_contacts_types.dart';

/// Синхронизация адресной книги телефона с HAN Eat (веб-заглушка).
class PhoneContactsService {
  PhoneContactsService._();

  static Future<bool> requestPermission() async => false;

  static Future<void> addContactToDevice({
    required String displayName,
    required String phoneRaw,
    String defaultRegion = 'RU',
  }) {
    throw UnsupportedError('Контакты недоступны в веб-версии');
  }

  static Future<PhoneContactsSyncResult> syncFromDevice({
    String defaultRegion = 'RU',
  }) {
    throw UnsupportedError('Синхронизация контактов недоступна в веб-версии');
  }
}
