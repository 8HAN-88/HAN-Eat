import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/auth_sessions_service.dart';

void main() {
  AuthSessionInfo session({
    String? deviceName,
    String? devicePlatform,
  }) {
    return AuthSessionInfo(
      id: 13,
      isCurrent: false,
      createdAt: DateTime.utc(2026, 9, 19),
      lastSeenAt: DateTime.utc(2026, 9, 19),
      deviceName: deviceName,
      devicePlatform: devicePlatform,
      ipAddress: '1.2.3.4',
    );
  }

  test('session title prefers stored device name', () {
    expect(session(deviceName: 'HanWe browser').title, 'HanWe browser');
  });

  test('session title maps platform when name is empty', () {
    expect(session(devicePlatform: 'web').title, 'Браузер');
    expect(session(devicePlatform: 'ios').title, 'iPhone');
    expect(session().title, 'Браузер');
  });
}
