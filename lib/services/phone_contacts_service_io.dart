import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/phone/phone_hash.dart';
import 'phone_contacts_sync_core.dart';
import 'phone_contacts_types.dart';

/// Синхронизация адресной книги телефона с HAN Eat (как в Telegram).
class PhoneContactsService {
  PhoneContactsService._();

  static bool get supportsContactPicker => false;

  static Future<bool> _requestContactsPermission({
    PermissionType type = PermissionType.read,
  }) async {
    final status = await FlutterContacts.permissions.request(type);
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  static Future<bool> requestPermission() async {
    return _requestContactsPermission();
  }

  static Future<int> importFromPicker() async => 0;

  /// Сохранить контакт в телефонную книгу устройства.
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

    final granted = await _requestContactsPermission(type: PermissionType.readWrite);
    if (!granted) {
      throw PhoneContactsPermissionDenied();
    }

    final contact = Contact(
      name: Name(first: name),
      phones: [
        Phone(
          number: e164,
          normalizedNumber: e164,
          label: const Label(PhoneLabel.mobile),
        ),
      ],
    );
    await FlutterContacts.create(contact);
  }

  /// Прочитать телефонную книгу и (по возможности) сопоставить с пользователями HAN Eat.
  static Future<PhoneContactsSyncResult> syncFromDevice({
    String defaultRegion = 'RU',
  }) async {
    final granted = await _requestContactsPermission();
    if (!granted) {
      throw PhoneContactsPermissionDenied();
    }

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    final hashToName = <String, String>{};
    final hashToE164 = <String, String>{};
    final hashes = <String>{};

    for (final contact in contacts) {
      final label = (contact.displayName ?? '').trim();
      for (final phone in contact.phones) {
        collectPhoneHashes(
          displayName: label.isNotEmpty ? label : phone.number,
          phoneRaw: phone.normalizedNumber ?? phone.number,
          hashToName: hashToName,
          hashToE164: hashToE164,
          hashes: hashes,
          defaultRegion: defaultRegion,
        );
      }
    }

    return buildPhoneContactsSyncResult(
      hashToName: hashToName,
      hashToE164: hashToE164,
      hashes: hashes,
    );
  }
}
