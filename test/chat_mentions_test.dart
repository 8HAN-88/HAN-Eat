import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_mentions.dart';

void main() {
  group('messageContentMentionsUser', () {
    test('matches @username @id @all @admin', () {
      expect(
        messageContentMentionsUser(
          content: 'hey @alice',
          isMine: false,
          userId: 1,
          username: 'alice',
        ),
        isTrue,
      );
      expect(
        messageContentMentionsUser(
          content: 'ping @id42',
          isMine: false,
          userId: 42,
        ),
        isTrue,
      );
      expect(
        messageContentMentionsUser(
          content: 'hello @all',
          isMine: false,
          userId: 1,
        ),
        isTrue,
      );
      expect(
        messageContentMentionsUser(
          content: '@admin please',
          isMine: false,
          userId: 1,
          amIGroupAdmin: true,
        ),
        isTrue,
      );
      expect(
        messageContentMentionsUser(
          content: '@admin please',
          isMine: false,
          userId: 1,
          amIGroupAdmin: false,
        ),
        isFalse,
      );
      expect(
        messageContentMentionsUser(
          content: 'hey @alice',
          isMine: true,
          userId: 1,
          username: 'alice',
        ),
        isFalse,
      );
    });
  });

  group('collectMentionMessageIds', () {
    test('collects from start id onward', () {
      final ids = collectMentionMessageIds(
        messages: [
          (id: 1, content: '@alice hi', isMine: false),
          (id: 2, content: 'nope', isMine: false),
          (id: 3, content: '@alice again', isMine: false),
          (id: 4, content: '@alice mine', isMine: true),
        ],
        fromMessageId: 2,
        userId: 1,
        username: 'alice',
      );
      expect(ids, [3]);
    });
  });

  group('remainingMentionJumps', () {
    test('counts leftover after cursor', () {
      expect(remainingMentionJumps([1, 2, 3], 0), 3);
      expect(remainingMentionJumps([1, 2, 3], 2), 1);
      expect(remainingMentionJumps([1, 2, 3], 3), 0);
      expect(remainingMentionJumps(const [], 0), 0);
    });
  });
}
