const String voicePrivacyEverybody = 'everybody';
const String voicePrivacyContacts = 'contacts';
const String voicePrivacyNobody = 'nobody';

const List<String> voicePrivacyValues = [
  voicePrivacyEverybody,
  voicePrivacyContacts,
  voicePrivacyNobody,
];

String normalizeVoicePrivacy(String? raw) {
  final key = raw?.trim().toLowerCase();
  if (key != null && voicePrivacyValues.contains(key)) return key;
  return voicePrivacyEverybody;
}

String voicePrivacyLabel(String privacy) {
  switch (normalizeVoicePrivacy(privacy)) {
    case voicePrivacyContacts:
      return 'Мои контакты';
    case voicePrivacyNobody:
      return 'Никто';
    case voicePrivacyEverybody:
    default:
      return 'Все';
  }
}
