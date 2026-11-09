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

/// A live read event counts only messages the member had not already read.
bool groupReadReceiptCovers({
  required int messageId,
  required int previousCursor,
  required int readUpTo,
}) {
  return messageId > previousCursor && messageId <= readUpTo;
}
