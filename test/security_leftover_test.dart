import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/settings/application/last_seen_privacy.dart';
import 'package:han_eat/services/auth_sessions_service.dart';
import 'package:han_eat/services/chat_service.dart';
import 'package:han_eat/services/totp_auth_service.dart';

void main() {
  test('active sessions keep loose maps and web nums', () {
    final sessions = AuthSessionsService.parseSessionList({
      'items': [
        <dynamic, dynamic>{
          'id': 7.0,
          'is_current': true,
          'created_at': '2026-01-01T00:00:00.000Z',
          'last_seen_at': '2026-01-01T01:00:00.000Z',
          'device_name': 'Safari',
          'device_platform': 'web',
          'ip_address': '1.2.3.4',
        },
        <dynamic, dynamic>{
          'id': '11',
          'is_current': false,
          'created_at': '2026-01-01T00:00:00.000Z',
          'last_seen_at': '2026-01-01T00:30:00.000Z',
          'device_platform': 'ios',
        },
        <dynamic, dynamic>{'id': 0, 'device_name': 'мусор'},
        'bad',
      ],
    });
    expect(sessions, hasLength(2));
    expect(sessions.first.id, 7);
    expect(sessions.first.isCurrent, isTrue);
    expect(sessions.first.title, 'Safari');
    expect(sessions.last.id, 11);
    expect(sessions.last.title, 'iPhone');
  });

  test('2FA status and setup parse loose maps', () {
    expect(TotpAuthService.parseStatus({'enabled': true}), isTrue);
    expect(TotpAuthService.parseStatus(<dynamic, dynamic>{'enabled': 1}), isTrue);
    expect(TotpAuthService.parseStatus({'enabled': 'true'}), isTrue);
    expect(TotpAuthService.parseStatus({'enabled': false}), isFalse);
    expect(TotpAuthService.parseStatus('bad'), isFalse);

    final setup = TotpAuthService.parseSetup(<dynamic, dynamic>{
      'secret': 'JBSWY3DPEHPK3PXP',
      'otpauth_uri': 'otpauth://totp/HanWe:user?secret=JBSWY3DPEHPK3PXP',
      'issuer': 'HanWe',
    });
    expect(setup.secret, 'JBSWY3DPEHPK3PXP');
    expect(setup.otpauthUri, contains('otpauth://totp/'));
    expect(setup.issuer, 'HanWe');
  });

  test('blocked list and last-seen privacy stay usable', () {
    final blocked = ChatService.parseMemberList({
      'items': [
        <dynamic, dynamic>{'id': 15.0, 'name': 'Боря'},
        <dynamic, dynamic>{'id': 0, 'name': 'мусор'},
        'bad',
      ],
    });
    expect(blocked.single.id, 15);
    expect(blocked.single.displayName, 'Боря');
    expect(normalizeLastSeenPrivacy('CONTACTS'), lastSeenPrivacyContacts);
    expect(normalizeLastSeenPrivacy(null, showLastSeen: false), lastSeenPrivacyNobody);
    expect(showLastSeenFromPrivacy(lastSeenPrivacyEverybody), isTrue);
    expect(lastSeenPrivacyLabel(lastSeenPrivacyNobody), 'Никто');
  });
}
