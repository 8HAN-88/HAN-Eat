// Helpers for Telegram-like unread reaction jump in chat threads.

bool messageHasReactionJump({
  required bool isMine,
  required bool hasReactions,
}) {
  return isMine && hasReactions;
}

/// Message ids (oldest → newest) that are mine and have reactions.
///
/// When [fromMessageId] is set, only messages at/after that id are included.
List<int> collectReactionMessageIds({
  required List<({int id, bool isMine, bool hasReactions})> messages,
  int? fromMessageId,
}) {
  if (messages.isEmpty) return const [];
  var start = 0;
  if (fromMessageId != null) {
    final idx = messages.indexWhere((m) => m.id == fromMessageId);
    if (idx >= 0) start = idx;
  }
  final out = <int>[];
  for (var i = start; i < messages.length; i++) {
    final m = messages[i];
    if (messageHasReactionJump(
      isMine: m.isMine,
      hasReactions: m.hasReactions,
    )) {
      out.add(m.id);
    }
  }
  return out;
}

/// Remaining reaction jumps after [cursor] advances through [queue].
int remainingReactionJumps(List<int> queue, int cursor) {
  if (queue.isEmpty) return 0;
  final left = queue.length - cursor;
  return left < 0 ? 0 : left;
}
