import '../models/chat_models.dart';

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

/// Контакт из телефона, которого ещё нет в HanWe.
class PhoneContactInvite {
  const PhoneContactInvite({
    required this.displayName,
    required this.phoneE164,
  });

  final String displayName;
  final String phoneE164;
}

/// Одна строка телефонной книги: всегда видна локально, опционально найдена в HanWe.
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
