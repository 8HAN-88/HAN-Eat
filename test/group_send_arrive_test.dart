import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_models.dart';
import 'package:han_eat/services/chat_service.dart';
import 'package:han_eat/services/chat_stream_service.dart';

void main() {
  test('sent group message parses web nums and stays in the thread', () {
    final sent = ChatService.parseMessage({
      'id': 90.0,
      'conversation_id': '21',
      'sender_id': 7.0,
      'sender_name': 'Я',
      'type': 'text',
      'content': 'Привет всем',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_mine': true,
      'is_delivered': false,
      'is_read': false,
      'read_count': 0.0,
      'client_message_id': 'c-1',
    });
    expect(sent.id, 90);
    expect(sent.conversationId, 21);
    expect(sent.senderId, 7);
    expect(sent.content, 'Привет всем');
    expect(sent.isMine, isTrue);
    expect(sent.clientMessageId, 'c-1');
    expect(sent.isDelivered, isFalse);
  });

  test('history and poll keep incoming group messages from loose maps', () {
    final page = ChatService.parseMessagePage({
      'items': [
        <dynamic, dynamic>{
          'id': 91.0,
          'conversation_id': 21.0,
          'sender_id': '11',
          'sender_name': 'Аня',
          'type': 'text',
          'content': 'Дошло',
          'created_at': '2026-01-01T00:00:01.000Z',
          'is_mine': false,
          'reactions': [
            <dynamic, dynamic>{'emoji': '👍', 'count': 2.0, 'me': false},
          ],
        },
        <dynamic, dynamic>{'id': 0, 'content': 'мусор'},
        'bad',
      ],
      'has_more': true,
      'next_cursor': 80.0,
      'pinned_messages': [
        <dynamic, dynamic>{
          'id': 70.0,
          'conversation_id': 21.0,
          'sender_id': 7.0,
          'content': 'Закреп',
          'created_at': '2026-01-01T00:00:00.000Z',
        },
      ],
    });
    expect(page.items, hasLength(1));
    expect(page.items.single.content, 'Дошло');
    expect(page.items.single.senderId, 11);
    expect(page.items.single.reactions, hasLength(1));
    expect(page.items.single.reactions.single.count, 2);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 80);
    expect(page.pinnedMessage?.id, 70);
    expect(page.pinnedMessages.single.content, 'Закреп');

    final fresh = ChatService.parseMessageList({
      'items': [
        <dynamic, dynamic>{
          'id': 92.0,
          'conversation_id': 21.0,
          'sender_id': 11.0,
          'content': 'Ещё одно',
          'created_at': '2026-01-01T00:00:02.000Z',
        },
      ],
    });
    expect(fresh.single.id, 92);
    expect(fresh.single.content, 'Ещё одно');
  });

  test('SSE payload arrives and delivery receipts accept web nums', () {
    final event = ChatStreamService.parseEvent(<dynamic, dynamic>{
      'type': 'message.new',
      'message': <dynamic, dynamic>{
        'id': 93.0,
        'conversation_id': 21.0,
        'sender_id': 11.0,
        'sender_name': 'Аня',
        'type': 'text',
        'content': 'Сейчас',
        'created_at': '2026-01-01T00:00:03.000Z',
        'is_mine': false,
      },
    });
    expect(event, isNotNull);
    expect(event!['type'], 'message.new');
    expect(ChatStreamService.parseEvent({'type': 'ping'}), isNull);

    final arrived = ChatService.messageFromStreamPayload(
      event['message'] as Map,
    );
    expect(arrived.id, 93);
    expect(arrived.content, 'Сейчас');
    expect(arrived.isMine, isFalse);

    expect(ChatService.parseEventInt(90.0), 90);
    expect(ChatService.parseEventInt('91'), 91);
    expect(ChatService.parseEventInt(null), isNull);
    expect(
      ChatService.parseEventInt(<dynamic, dynamic>{}['id']),
      isNull,
    );
  });

  test('own outgoing from stream starts undelivered until receipts arrive', () {
    final incoming = ChatService.messageFromStreamPayload({
      'id': 94.0,
      'conversation_id': 21.0,
      'sender_id': 7.0,
      'content': 'Моё',
      'created_at': '2026-01-01T00:00:04.000Z',
      'is_mine': true,
      'is_delivered': true,
      'is_read': true,
      'read_count': 2.0,
    });
    expect(incoming.id, 94);
    expect(incoming.content, 'Моё');
    expect(incoming.readCount, 2);
  });
}
