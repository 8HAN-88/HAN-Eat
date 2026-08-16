import '../../../models/chat_models.dart';

/// Local reaction toggle so the chip flips before the server answers.
List<ChatReactionSummary> optimisticToggleReactions({
  required List<ChatReactionSummary> current,
  required String emoji,
}) {
  final target = emoji.trim();
  if (target.isEmpty) return current;
  final mine = current.where((r) => r.reactedByMe).toList();
  final removing = mine.any((r) => r.emoji == target);
  final next = <ChatReactionSummary>[];
  var found = false;
  for (final row in current) {
    if (row.emoji == target) {
      found = true;
      if (removing) {
        final count = row.count - 1;
        if (count > 0) {
          next.add(
            ChatReactionSummary(
              emoji: row.emoji,
              count: count,
              starsTotal: row.starsTotal,
            ),
          );
        }
      } else if (!row.reactedByMe) {
        next.add(
          ChatReactionSummary(
            emoji: row.emoji,
            count: row.count + 1,
            reactedByMe: true,
            starsTotal: row.starsTotal,
          ),
        );
      } else {
        next.add(row);
      }
      continue;
    }
    if (!removing && row.reactedByMe) {
      final count = row.count - 1;
      if (count > 0) {
        next.add(
          ChatReactionSummary(
            emoji: row.emoji,
            count: count,
            starsTotal: row.starsTotal,
          ),
        );
      }
      continue;
    }
    next.add(row);
  }
  if (!removing && !found) {
    next.add(ChatReactionSummary(emoji: target, count: 1, reactedByMe: true));
  }
  return next;
}
