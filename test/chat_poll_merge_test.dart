import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_models.dart';

void main() {
  test('patchChatPollClosedInContent sets is_closed flag', () {
    final raw = jsonEncode({
      'poll': {
        'question': 'Обед?',
        'options': [
          {'index': 0, 'text': 'Пицца'},
          {'index': 1, 'text': 'Суши'},
        ],
        'is_closed': false,
      },
    });

    final patched = patchChatPollClosedInContent(raw, isClosed: true);
    final data = jsonDecode(patched) as Map<String, dynamic>;
    expect(data['poll']['is_closed'], isTrue);
  });

  test('applyIncomingChatMessagePreservingLocalPoll keeps closed state', () {
    const closedContent = '{"poll":{"question":"Q?","options":[{"index":0,"text":"A"},{"index":1,"text":"B"}],"is_closed":true}}';
    const openContent = '{"poll":{"question":"Q?","options":[{"index":0,"text":"A"},{"index":1,"text":"B"}],"is_closed":false}}';

    final local = ChatMessage(
      id: 1,
      conversationId: 10,
      senderId: 5,
      type: 'poll',
      content: closedContent,
      createdAt: DateTime(2024, 1, 1),
      isMine: true,
    );
    final incoming = ChatMessage(
      id: 1,
      conversationId: 10,
      senderId: 5,
      type: 'poll',
      content: openContent,
      createdAt: DateTime(2024, 1, 1),
      isMine: true,
    );

    final merged = applyIncomingChatMessagePreservingLocalPoll(local, incoming);
    expect(merged.poll?.isClosed, isTrue);
  });

  test('applyIncomingChatMessagePreservingLocalPoll passes through when open', () {
    const openContent = '{"poll":{"question":"Q?","options":[{"index":0,"text":"A"},{"index":1,"text":"B"}],"is_closed":false}}';

    final local = ChatMessage(
      id: 1,
      conversationId: 10,
      senderId: 5,
      type: 'poll',
      content: openContent,
      createdAt: DateTime(2024, 1, 1),
    );
    final incoming = local;

    final merged = applyIncomingChatMessagePreservingLocalPoll(local, incoming);
    expect(merged.poll?.isClosed, isFalse);
  });
}
