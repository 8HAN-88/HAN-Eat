import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_reaction_jumps.dart';

void main() {
  group('messageHasReactionJump', () {
    test('only mine with reactions', () {
      expect(
        messageHasReactionJump(isMine: true, hasReactions: true),
        isTrue,
      );
      expect(
        messageHasReactionJump(isMine: true, hasReactions: false),
        isFalse,
      );
      expect(
        messageHasReactionJump(isMine: false, hasReactions: true),
        isFalse,
      );
    });
  });

  group('collectReactionMessageIds', () {
    test('collects mine+reactions from start id onward', () {
      final ids = collectReactionMessageIds(
        messages: [
          (id: 1, isMine: true, hasReactions: true),
          (id: 2, isMine: false, hasReactions: true),
          (id: 3, isMine: true, hasReactions: false),
          (id: 4, isMine: true, hasReactions: true),
        ],
        fromMessageId: 2,
      );
      expect(ids, [4]);
    });

    test('collects all when fromMessageId is null', () {
      final ids = collectReactionMessageIds(
        messages: [
          (id: 1, isMine: true, hasReactions: true),
          (id: 2, isMine: false, hasReactions: true),
          (id: 3, isMine: true, hasReactions: true),
        ],
      );
      expect(ids, [1, 3]);
    });
  });

  group('remainingReactionJumps', () {
    test('counts leftover after cursor', () {
      expect(remainingReactionJumps([1, 2, 3], 0), 3);
      expect(remainingReactionJumps([1, 2, 3], 2), 1);
      expect(remainingReactionJumps([1, 2, 3], 3), 0);
      expect(remainingReactionJumps(const [], 0), 0);
    });
  });
}
