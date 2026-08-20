const String groupAddPrivacyEverybody = 'everybody';
const String groupAddPrivacyContacts = 'contacts';
const String groupAddPrivacyNobody = 'nobody';

const List<String> groupAddPrivacyValues = [
  groupAddPrivacyEverybody,
  groupAddPrivacyContacts,
  groupAddPrivacyNobody,
];

String normalizeGroupAddPrivacy(String? raw) {
  final key = raw?.trim().toLowerCase();
  if (key != null && groupAddPrivacyValues.contains(key)) return key;
  return groupAddPrivacyEverybody;
}

String groupAddPrivacyLabel(String privacy) {
  switch (normalizeGroupAddPrivacy(privacy)) {
    case groupAddPrivacyContacts:
      return 'Мои контакты';
    case groupAddPrivacyNobody:
      return 'Никто';
    case groupAddPrivacyEverybody:
    default:
      return 'Все';
  }
}
