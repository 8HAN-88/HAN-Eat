import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_auto_delete.dart';
import 'package:han_eat/services/user_realtime_service.dart';

void main() {
  group('chat auto-delete helpers', () {
    final created = DateTime.utc(2026, 8, 7, 12, 0, 0);

    test('disabled TTL never expires', () {
      expect(isMessageAutoDeleted(created, 0), isFalse);
      expect(messageAutoDeleteExpiresAt(created, 0), isNull);
      expect(formatAutoDeleteRemaining(created, 0), '');
    });

    test('expires after TTL', () {
      final now = created.add(const Duration(hours: 25));
      expect(
        isMessageAutoDeleted(created, 24 * 3600, now: now),
        isTrue,
      );
      expect(
        isMessageAutoDeleted(created, 24 * 3600, now: created.add(const Duration(hours: 23))),
        isFalse,
      );
    });

    test('remaining label formats', () {
      expect(
        formatAutoDeleteRemaining(
          created,
          24 * 3600,
          now: created.add(const Duration(hours: 2)),
        ),
        '22ч',
      );
      expect(
        formatAutoDeleteRemaining(
          created,
          3600,
          now: created.add(const Duration(minutes: 10)),
        ),
        '50м',
      );
      expect(
        formatAutoDeleteRemaining(
          created,
          120,
          now: created.add(const Duration(seconds: 90)),
        ),
        '30с',
      );
      expect(
        formatAutoDeleteRemaining(
          created,
          7 * 24 * 3600,
          now: created.add(const Duration(days: 1)),
        ),
        '6д',
      );
    });
  });

  group('UserRealtimeEvent chat.auto_delete', () {
    test('parses auto_delete_seconds', () {
      final event = UserRealtimeEvent.fromJson({
        'event': 'chat.auto_delete',
        'conversation_id': 42,
        'auto_delete_seconds': 86400,
      });
      expect(event.event, 'chat.auto_delete');
      expect(event.conversationId, 42);
      expect(event.autoDeleteSeconds, 86400);
    });
  });
}
