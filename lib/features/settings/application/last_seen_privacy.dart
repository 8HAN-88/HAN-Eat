// Telegram-like last-seen visibility tiers.

const String lastSeenPrivacyEverybody = 'everybody';
const String lastSeenPrivacyContacts = 'contacts';
const String lastSeenPrivacyNobody = 'nobody';

const List<String> lastSeenPrivacyValues = [
  lastSeenPrivacyEverybody,
  lastSeenPrivacyContacts,
  lastSeenPrivacyNobody,
];

String normalizeLastSeenPrivacy(String? raw, {bool? showLastSeen}) {
  final key = raw?.trim().toLowerCase();
  if (key != null && lastSeenPrivacyValues.contains(key)) return key;
  if (showLastSeen == false) return lastSeenPrivacyNobody;
  return lastSeenPrivacyEverybody;
}

bool showLastSeenFromPrivacy(String privacy) =>
    privacy != lastSeenPrivacyNobody;

String lastSeenPrivacyLabel(String privacy) {
  switch (normalizeLastSeenPrivacy(privacy)) {
    case lastSeenPrivacyContacts:
      return 'Мои контакты';
    case lastSeenPrivacyNobody:
      return 'Никто';
    case lastSeenPrivacyEverybody:
    default:
      return 'Все';
  }
}
