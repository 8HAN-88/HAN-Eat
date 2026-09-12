import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_open_anchor.dart';

void main() {
  group('resolveChatOpenTarget', () {
    test('deep link wins over unread and saved position', () {
      final target = resolveChatOpenTarget(
        jumpToMessageId: 9,
        firstUnreadId: 3,
        savedMessageId: 5,
      );
      expect(target.kind, ChatOpenKind.message);
      expect(target.messageId, 9);
    });

    test('unread wins over saved mid-history', () {
      final target = resolveChatOpenTarget(
        firstUnreadId: 3,
        savedMessageId: 5,
      );
      expect(target.kind, ChatOpenKind.unread);
      expect(target.messageId, 3);
    });

    test('saved position is used when everything is read', () {
      final target = resolveChatOpenTarget(savedMessageId: 5);
      expect(target.kind, ChatOpenKind.message);
      expect(target.messageId, 5);
    });

    test('falls back to the last message', () {
      final target = resolveChatOpenTarget();
      expect(target.kind, ChatOpenKind.bottom);
      expect(target.isBottom, isTrue);
      expect(target.fractionFor(messageIndex: null, length: 20), 1);
    });
  });

  group('chatUnreadIsBelowViewport', () {
    test('reversed list: scrolled up means unread is toward latest', () {
      expect(
        chatUnreadIsBelowViewport(
          offset: 400,
          unreadApprox: 0,
          reversed: true,
        ),
        isTrue,
      );
      expect(
        chatUnreadIsBelowViewport(
          offset: 0,
          unreadApprox: 0,
          reversed: true,
        ),
        isFalse,
      );
    });

    test('forward list: unread below when offset is still above it', () {
      expect(
        chatUnreadIsBelowViewport(
          offset: 40,
          unreadApprox: 500,
        ),
        isTrue,
      );
      expect(
        chatUnreadIsBelowViewport(
          offset: 500,
          unreadApprox: 500,
        ),
        isFalse,
      );
    });
  });

  group('firstUnreadMessageId', () {
    test('skips own messages when counting unread', () {
      final id = firstUnreadMessageId(
        unreadCount: 2,
        messagesOldestFirst: const [
          (id: 1, isMine: false),
          (id: 2, isMine: true),
          (id: 3, isMine: false),
          (id: 4, isMine: false),
        ],
      );
      expect(id, 3);
    });

    test('returns null when the chat is fully read', () {
      expect(
        firstUnreadMessageId(
          unreadCount: 0,
          messagesOldestFirst: const [(id: 1, isMine: false)],
        ),
        isNull,
      );
    });
  });
}
