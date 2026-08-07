// Helpers for Telegram-like unread @mention jump in chat threads.

bool messageContentMentionsUser({
  required String content,
  required bool isMine,
  required int userId,
  String? username,
  bool amIGroupAdmin = false,
}) {
  if (isMine) return false;
  if (content.isEmpty) return false;
  if (RegExp(r'(?<!\w)@id' + RegExp.escape('$userId') + r'\b')
      .hasMatch(content)) {
    return true;
  }
  if (RegExp(r'(?<!\w)@all\b', caseSensitive: false).hasMatch(content)) {
    return true;
  }
  final uname = username?.trim().toLowerCase();
  if (uname != null && uname.isNotEmpty) {
    final handle = uname.startsWith('@') ? uname.substring(1) : uname;
    if (handle.isNotEmpty &&
        RegExp(
          r'(?<!\w)@' + RegExp.escape(handle) + r'\b',
          caseSensitive: false,
        ).hasMatch(content)) {
      return true;
    }
  }
  if (amIGroupAdmin &&
      RegExp(r'(?<!\w)@admins?\b', caseSensitive: false).hasMatch(content)) {
    return true;
  }
  return false;
}

/// Message ids (oldest → newest) that mention the user, starting at [fromMessageId].
List<int> collectMentionMessageIds({
  required List<({int id, String content, bool isMine})> messages,
  required int? fromMessageId,
  required int userId,
  String? username,
  bool amIGroupAdmin = false,
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
    if (messageContentMentionsUser(
      content: m.content,
      isMine: m.isMine,
      userId: userId,
      username: username,
      amIGroupAdmin: amIGroupAdmin,
    )) {
      out.add(m.id);
    }
  }
  return out;
}

/// Remaining mention jumps after [cursor] advances through [queue].
int remainingMentionJumps(List<int> queue, int cursor) {
  if (queue.isEmpty) return 0;
  final left = queue.length - cursor;
  return left < 0 ? 0 : left;
}
