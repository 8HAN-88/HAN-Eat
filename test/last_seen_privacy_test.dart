import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/settings/application/last_seen_privacy.dart';

void main() {
  group('normalizeLastSeenPrivacy', () {
    test('accepts known tiers and falls back', () {
      expect(normalizeLastSeenPrivacy('contacts'), lastSeenPrivacyContacts);
      expect(normalizeLastSeenPrivacy(null, showLastSeen: false), lastSeenPrivacyNobody);
      expect(normalizeLastSeenPrivacy(null, showLastSeen: true), lastSeenPrivacyEverybody);
      expect(normalizeLastSeenPrivacy('weird'), lastSeenPrivacyEverybody);
    });
  });

  group('labels', () {
    test('maps tiers to Russian labels', () {
      expect(lastSeenPrivacyLabel(lastSeenPrivacyEverybody), 'Все');
      expect(lastSeenPrivacyLabel(lastSeenPrivacyContacts), 'Мои контакты');
      expect(lastSeenPrivacyLabel(lastSeenPrivacyNobody), 'Никто');
    });
  });
}
