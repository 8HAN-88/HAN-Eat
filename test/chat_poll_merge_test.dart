import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_models.dart';
import 'package:han_eat/models/chat_poll.dart';

void main() {
  test('ChatPollMessage parses closes_at and effective closed', () {
    final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    final poll = ChatPollMessage.fromJson({
      'question': 'Обед?',
      'options': [
        {'index': 0, 'text': 'Пицца'},
        {'index': 1, 'text': 'Суши'},
      ],
      'is_closed': false,
      'closes_at': past.toIso8601String(),
    });
    expect(poll.closesAt, isNotNull);
    expect(poll.isEffectivelyClosed, isTrue);
    expect(formatPollTimeRemaining(past), isNull);
  });

  test('formatPollTimeRemaining shows hours', () {
    final closes = DateTime.now().toUtc().add(const Duration(hours: 2, minutes: 15));
    final label = formatPollTimeRemaining(closes);
    expect(label, contains('осталось'));
    expect(label, contains('ч'));
  });

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
