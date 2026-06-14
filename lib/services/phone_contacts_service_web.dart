import '../core/phone/phone_hash.dart';
import 'phone_contacts_picker_web.dart';
import 'phone_contacts_store_web.dart';
import 'phone_contacts_sync_core.dart';
import 'phone_contacts_types.dart';

/// Синхронизация контактов в веб-версии: Contact Picker API + локальное хранение.
class PhoneContactsService {
  PhoneContactsService._();

  static bool get supportsContactPicker => PhoneContactsPickerWeb.isSupported;

  static Future<bool> requestPermission() async => supportsContactPicker;

  /// Импорт из системной телефонной книги через Contact Picker (жест пользователя).
  static Future<int> importFromPicker() async {
    final picked = await PhoneContactsPickerWeb.pick();
    if (picked.isEmpty) return 0;
    final merged = await WebPhoneContactsStore.merge(picked);
    return merged.length;
  }

  /// Сохранить контакт в локальной телефонной книге браузера.
  static Future<void> addContactToDevice({
    required String displayName,
    required String phoneRaw,
    String defaultRegion = 'RU',
  }) async {
    final name = displayName.trim();
    if (name.isEmpty) {
      throw PhoneContactsInvalidInput('Укажите имя контакта');
    }

    final e164 = normalizePhoneE164(phoneRaw, defaultRegion: defaultRegion);
    if (e164 == null) {
      throw PhoneContactsInvalidInput('Некорректный номер телефона');
    }

    await WebPhoneContactsStore.merge([
      WebPhoneBookEntry(displayName: name, phoneE164: e164),
    ]);
  }

  /// Сопоставить сохранённые контакты с пользователями HAN Eat.
  static Future<PhoneContactsSyncResult> syncFromDevice({
    String defaultRegion = 'RU',
  }) async {
    final stored = await WebPhoneContactsStore.load();
    final hashToName = <String, String>{};
    final hashToE164 = <String, String>{};
    final hashes = <String>{};

    for (final entry in stored) {
      collectPhoneHashes(
        displayName: entry.displayName,
        phoneRaw: entry.phoneE164,
        hashToName: hashToName,
        hashToE164: hashToE164,
        hashes: hashes,
        defaultRegion: defaultRegion,
      );
    }

    return buildPhoneContactsSyncResult(
      hashToName: hashToName,
      hashToE164: hashToE164,
      hashes: hashes,
    );
  }
}
