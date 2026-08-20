const String dmPrivacyEverybody = 'everybody';
const String dmPrivacyContacts = 'contacts';
const String dmPrivacyNobody = 'nobody';

const List<String> dmPrivacyValues = [
  dmPrivacyEverybody,
  dmPrivacyContacts,
  dmPrivacyNobody,
];

String normalizeDmPrivacy(String? raw) {
  final key = raw?.trim().toLowerCase();
  if (key != null && dmPrivacyValues.contains(key)) return key;
  return dmPrivacyEverybody;
}

String dmPrivacyLabel(String privacy) {
  switch (normalizeDmPrivacy(privacy)) {
    case dmPrivacyContacts:
      return 'Мои контакты';
    case dmPrivacyNobody:
      return 'Никто';
    case dmPrivacyEverybody:
    default:
      return 'Все';
  }
}
