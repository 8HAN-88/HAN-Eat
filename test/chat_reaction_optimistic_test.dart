import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_reaction_optimistic.dart';
import 'package:han_eat/models/chat_models.dart';

void main() {
  test('adds a new reaction as mine', () {
    final next = optimisticToggleReactions(
      current: const [
        ChatReactionSummary(emoji: '👍', count: 2),
      ],
      emoji: '🔥',
    );
    expect(next.map((r) => r.emoji), ['👍', '🔥']);
    expect(next.last.reactedByMe, isTrue);
    expect(next.last.count, 1);
  });

  test('removes my reaction and keeps others', () {
    final next = optimisticToggleReactions(
      current: const [
        ChatReactionSummary(emoji: '👍', count: 2, reactedByMe: true),
        ChatReactionSummary(emoji: '🔥', count: 1),
      ],
      emoji: '👍',
    );
    expect(next.single.emoji, '🔥');
    expect(next.single.reactedByMe, isFalse);
  });

  test('switching emoji moves my reaction', () {
    final next = optimisticToggleReactions(
      current: const [
        ChatReactionSummary(emoji: '👍', count: 1, reactedByMe: true),
      ],
      emoji: '😂',
    );
    expect(next.single.emoji, '😂');
    expect(next.single.reactedByMe, isTrue);
    expect(next.single.count, 1);
  });
}
