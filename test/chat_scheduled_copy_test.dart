import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_models.dart';

void main() {
  test('ScheduledChatMessage.copyWith updates content and sendAt', () {
    final item = ScheduledChatMessage(
      id: 3,
      conversationId: 9,
      senderId: 1,
      type: 'text',
      content: 'later',
      sendAt: DateTime.utc(2026, 8, 16, 12),
      status: 'pending',
      createdAt: DateTime.utc(2026, 8, 16, 10),
    );
    final next = item.copyWith(
      content: 'now',
      sendAt: DateTime.utc(2026, 8, 16, 18),
    );
    expect(next.content, 'now');
    expect(next.sendAt, DateTime.utc(2026, 8, 16, 18));
    expect(next.id, 3);
    expect(item.content, 'later');
  });
}
