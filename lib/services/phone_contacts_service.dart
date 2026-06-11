import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/phone/phone_hash.dart';
import '../models/chat_models.dart';
import 'chat_service.dart';

class PhoneContactMatch {
  const PhoneContactMatch({
    required this.user,
    this.addressBookName,
  });

  final ChatUserSearchItem user;
  final String? addressBookName;

  String get displayName {
    final fromBook = addressBookName?.trim();
    if (fromBook != null && fromBook.isNotEmpty) return fromBook;
    return user.name ?? user.username ?? 'Пользователь';
  }
}

/// Контакт из телефона, которого ещё нет в HAN Eat.
class PhoneContactInvite {
  const PhoneContactInvite({
    required this.displayName,
    required this.phoneE164,
  });

  final String displayName;
  final String phoneE164;
}

/// Одна строка телефонной книги: всегда видна локально, опционально найдена в HAN Eat.
class PhoneBookContact {
  const PhoneBookContact({
    required this.displayName,
    required this.phoneE164,
    this.matchedUser,
  });

  final String displayName;
  final String phoneE164;
  final ChatUserSearchItem? matchedUser;

  bool get isOnHanEat => matchedUser != null;
}

class PhoneContactsSyncResult {
  const PhoneContactsSyncResult({
    required this.phoneBook,
    required this.onApp,
    required this.invitees,
    this.apiError,
  });

  final List<PhoneBookContact> phoneBook;
  final List<PhoneContactMatch> onApp;
  final List<PhoneContactInvite> invitees;
  final Object? apiError;
}

/// Пользователь отклонил доступ к адресной книге.
class PhoneContactsPermissionDenied implements Exception {
  @override
  String toString() => 'Нет доступа к контактам телефона';
}

class PhoneContactsInvalidInput implements Exception {
  PhoneContactsInvalidInput(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Синхронизация адресной книги телефона с HAN Eat (как в Telegram).
class PhoneContactsService {
  PhoneContactsService._();

  static const _maxInvitees = 500;
  static const _apiBatchSize = 500;

  static Future<bool> _requestContactsPermission({
    PermissionType type = PermissionType.read,
  }) async {
    final status = await FlutterContacts.permissions.request(type);
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    return _requestContactsPermission();
  }

  /// Сохранить контакт в телефонную книгу устройства.
  static Future<void> addContactToDevice({
    required String displayName,
    required String phoneRaw,
    String defaultRegion = 'RU',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Контакты недоступны в веб-версии');
    }

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

  static Future<List<ChatUserSearchItem>> _matchHashesInBatches(
    List<String> hashes,
  ) async {
    final out = <ChatUserSearchItem>[];
    for (var i = 0; i < hashes.length; i += _apiBatchSize) {
      final end = (i + _apiBatchSize).clamp(0, hashes.length);
      final batch = hashes.sublist(i, end);
      final items = await ChatService.syncPhoneContacts(batch);
      out.addAll(items);
    }
    return out;
  }

  /// Прочитать телефонную книгу и (по возможности) сопоставить с пользователями HAN Eat.
  static Future<PhoneContactsSyncResult> syncFromDevice({
    String defaultRegion = 'RU',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Синхронизация контактов недоступна в веб-версии');
    }

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
        final raw = phone.normalizedNumber ?? phone.number;
        final e164 = normalizePhoneE164(raw, defaultRegion: defaultRegion);
        if (e164 == null) continue;
        final hash = hashPhoneE164(e164);
        hashes.add(hash);
        hashToName.putIfAbsent(
          hash,
          () => label.isNotEmpty ? label : phone.number,
        );
        hashToE164.putIfAbsent(hash, () => e164);
      }
    }

    if (hashes.isEmpty) {
      return const PhoneContactsSyncResult(
        phoneBook: [],
        onApp: [],
        invitees: [],
      );
    }

    Object? apiError;
    List<ChatUserSearchItem> users = [];
    try {
      users = await _matchHashesInBatches(hashes.toList());
    } catch (e) {
      apiError = e;
    }

    final hashToUser = <String, ChatUserSearchItem>{};
    for (final u in users) {
      final h = u.phoneHash;
      if (h != null && h.isNotEmpty) {
        hashToUser[h] = u;
      }
    }

    final phoneBook = <PhoneBookContact>[];
    final onApp = <PhoneContactMatch>[];
    final invitees = <PhoneContactInvite>[];

    final sortedHashes = hashes.toList()
      ..sort(
        (a, b) => (hashToName[a] ?? '').compareTo(hashToName[b] ?? ''),
      );

    for (final hash in sortedHashes) {
      final e164 = hashToE164[hash];
      if (e164 == null) continue;
      final name = hashToName[hash] ?? e164;
      final matched = hashToUser[hash];
      phoneBook.add(
        PhoneBookContact(
          displayName: name,
          phoneE164: e164,
          matchedUser: matched,
        ),
      );
      if (matched != null) {
        onApp.add(
          PhoneContactMatch(
            user: matched,
            addressBookName: name,
          ),
        );
      } else if (invitees.length < _maxInvitees) {
        invitees.add(PhoneContactInvite(displayName: name, phoneE164: e164));
      }
    }

    return PhoneContactsSyncResult(
      phoneBook: phoneBook,
      onApp: onApp,
      invitees: invitees,
      apiError: apiError,
    );
  }
}
