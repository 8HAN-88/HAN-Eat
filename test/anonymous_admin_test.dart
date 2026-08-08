import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/anonymous_admin.dart';

void main() {
  group('canSendAnonymously', () {
    test('only group admins', () {
      expect(
        canSendAnonymously(isGroup: true, amIGroupAdmin: true),
        isTrue,
      );
      expect(
        canSendAnonymously(isGroup: true, amIGroupAdmin: false),
        isFalse,
      );
      expect(
        canSendAnonymously(isGroup: false, amIGroupAdmin: true),
        isFalse,
      );
    });
  });

  group('resolveAnonymousSenderLabel', () {
    test('hides real name from members', () {
      expect(
        resolveAnonymousSenderLabel(
          isAnonymous: true,
          groupTitle: 'Team',
          realSenderName: 'Alice',
          viewerIsSender: false,
          viewerIsAdmin: false,
        ),
        'Team',
      );
    });

    test('reveals to admins and sender', () {
      expect(
        resolveAnonymousSenderLabel(
          isAnonymous: true,
          groupTitle: 'Team',
          realSenderName: 'Alice',
          viewerIsSender: false,
          viewerIsAdmin: true,
        ),
        'Team (Alice)',
      );
    });
  });
}
