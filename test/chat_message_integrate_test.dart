import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_message_integrate.dart';
import 'package:han_eat/models/chat_models.dart';

ChatMessage _msg({
  required int id,
  required String content,
  String? clientMessageId,
  bool isMine = true,
  DateTime? createdAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 1,
    senderId: 7,
    type: 'text',
    content: content,
    createdAt: createdAt ?? DateTime(2026, 8, 16, 12),
    isMine: isMine,
    clientMessageId: clientMessageId,
  );
}

bool _dup(ChatMessage a, ChatMessage b) {
  final ca = (a.clientMessageId ?? '').trim();
  final cb = (b.clientMessageId ?? '').trim();
  if (ca.isNotEmpty && cb.isNotEmpty) return ca == cb;
  if (a.id > 0 && b.id > 0) return a.id == b.id;
  return a.isMine &&
      b.isMine &&
      a.content == b.content &&
      a.type == b.type;
}

void main() {
  group('integrateIncomingChatMessage', () {
    test('keeps other optimistic bubbles when one send confirms', () {
      final a = _msg(id: -1, content: 'one', clientMessageId: 'a');
      final b = _msg(id: -2, content: 'two', clientMessageId: 'b');
      final confirmed = _msg(id: 101, content: 'one', clientMessageId: 'a');

      final result = integrateIncomingChatMessage(
        messages: [a, b],
        incoming: confirmed,
        removeTempId: -1,
        isDuplicate: _dup,
        merge: (local, incoming) => incoming,
      );

      expect(result.added, isFalse);
      expect(result.messages.map((m) => m.id), [101, -2]);
      expect(result.messages.last.content, 'two');
    });

    test('matches by client_message_id without wiping same-text siblings', () {
      final first = _msg(id: -1, content: 'ok', clientMessageId: 'c1');
      final second = _msg(id: -2, content: 'ok', clientMessageId: 'c2');
      final confirmed = _msg(id: 55, content: 'ok', clientMessageId: 'c1');

      final result = integrateIncomingChatMessage(
        messages: [first, second],
        incoming: confirmed,
        isDuplicate: _dup,
        merge: (local, incoming) => incoming,
      );

      expect(result.messages.map((m) => m.clientMessageId), ['c1', 'c2']);
      expect(result.messages.first.id, 55);
      expect(result.messages.last.id, -2);
    });

    test('incoming peer message does not drop outgoing optimistic', () {
      final pending = _msg(id: -9, content: 'hello', clientMessageId: 'x');
      final peer = _msg(
        id: 80,
        content: 'hi',
        isMine: false,
        clientMessageId: null,
      );

      final result = integrateIncomingChatMessage(
        messages: [pending],
        incoming: peer,
        isDuplicate: _dup,
        merge: (local, incoming) => incoming,
      );

      expect(result.added, isTrue);
      expect(result.messages.map((m) => m.id), [-9, 80]);
    });
  });

  group('preserveOptimisticOutgoing', () {
    test('re-attaches in-flight bubbles after a full reload', () {
      final pending = _msg(id: -3, content: 'draft', clientMessageId: 'p');
      final server = _msg(id: 1, content: 'old', isMine: false);

      final out = preserveOptimisticOutgoing(
        previous: [server, pending],
        serverItems: [server],
        keepTempIds: {-3},
        isDuplicate: _dup,
      );

      expect(out.map((m) => m.id), [1, -3]);
    });

    test('keeps just-sent confirmed message missing from stale snapshot', () {
      final sent = _msg(id: 42, content: 'now', clientMessageId: 'n');
      final server = _msg(id: 10, content: 'old', isMine: false);

      final out = preserveOptimisticOutgoing(
        previous: [server, sent],
        serverItems: [server],
        keepTempIds: const {},
        isDuplicate: _dup,
      );

      expect(out.map((m) => m.id), [10, 42]);
    });
  });
}
