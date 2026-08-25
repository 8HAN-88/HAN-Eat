import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/app_invite_service.dart';

void main() {
  group('AppInviteService.inviteMessage', () {
    test('does not call empty name «Сообщение»', () {
      final text = AppInviteService.inviteMessage(inviterName: '');
      expect(text.contains('Сообщение приглашает'), isFalse);
      expect(text.startsWith('Привет!'), isTrue);
      expect(text.contains('Я приглашает вас в HanWe'), isTrue);
    });

    test('previews custom emoji in inviter name', () {
      final text = AppInviteService.inviteMessage(
        inviterName: 'Анна [[e:1]]',
      );
      expect(text.contains('Анна ✦ приглашает вас в HanWe'), isTrue);
      expect(text.contains('[[e:1]]'), isFalse);
    });
  });
}
