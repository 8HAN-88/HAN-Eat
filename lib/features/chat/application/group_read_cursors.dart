/// Keep the furthest cursor we have seen for each other group member.
Map<int, int> mergeGroupReadCursors(
  Map<int, int> current,
  Map<int, int> incoming,
) {
  if (incoming.isEmpty) return current;
  final next = Map<int, int>.from(current);
  for (final entry in incoming.entries) {
    if (entry.key <= 0 || entry.value <= 0) continue;
    final known = next[entry.key] ?? 0;
    if (entry.value > known) next[entry.key] = entry.value;
  }
  return next;
}

/// Replace cursors with the server snapshot, keeping a newer local value
/// for members who are still in the group.
Map<int, int> adoptGroupCursors(
  Map<int, int> current,
  Map<int, int> incoming,
) {
  if (incoming.isEmpty) return current;
  final next = <int, int>{};
  for (final entry in incoming.entries) {
    if (entry.key <= 0 || entry.value <= 0) continue;
    final known = current[entry.key] ?? 0;
    next[entry.key] = entry.value > known ? entry.value : known;
  }
  return next;
}

/// Double tick in a group: every other member has reached this message.
bool groupDeliveredToAll({
  required int messageId,
  required Map<int, int> cursors,
  required int otherMemberCount,
}) {
  if (messageId <= 0 || otherMemberCount <= 0) return false;
  if (cursors.length < otherMemberCount) return false;
  var covered = 0;
  for (final cursor in cursors.values) {
    if (cursor >= messageId) covered++;
  }
  return covered >= otherMemberCount;
}

/// A live read event counts only messages the member had not already read.
bool groupReadReceiptCovers({
  required int messageId,
  required int previousCursor,
  required int readUpTo,
}) {
  return messageId > previousCursor && messageId <= readUpTo;
}
