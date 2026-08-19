const String callPrivacyEverybody = 'everybody';
const String callPrivacyContacts = 'contacts';
const String callPrivacyNobody = 'nobody';

const List<String> callPrivacyValues = [
  callPrivacyEverybody,
  callPrivacyContacts,
  callPrivacyNobody,
];

String normalizeCallPrivacy(String? raw) {
  final key = raw?.trim().toLowerCase();
  if (key != null && callPrivacyValues.contains(key)) return key;
  return callPrivacyEverybody;
}

String callPrivacyLabel(String privacy) {
  switch (normalizeCallPrivacy(privacy)) {
    case callPrivacyContacts:
      return 'Мои контакты';
    case callPrivacyNobody:
      return 'Никто';
    case callPrivacyEverybody:
    default:
      return 'Все';
  }
}
