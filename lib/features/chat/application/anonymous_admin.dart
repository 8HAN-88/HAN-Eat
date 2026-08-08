// Telegram-like anonymous admin display helpers.

bool canSendAnonymously({
  required bool isGroup,
  required bool amIGroupAdmin,
}) {
  return isGroup && amIGroupAdmin;
}

/// Members see [groupTitle]; sender/admins see "Title (Real Name)".
String? resolveAnonymousSenderLabel({
  required bool isAnonymous,
  required String? groupTitle,
  required String? realSenderName,
  required bool viewerIsSender,
  required bool viewerIsAdmin,
}) {
  if (!isAnonymous) return realSenderName;
  final title = (groupTitle ?? '').trim();
  final safeTitle = title.isEmpty ? 'Группа' : title;
  if (viewerIsSender || viewerIsAdmin) {
    final real = (realSenderName ?? '').trim();
    final safeReal = real.isEmpty ? 'Админ' : real;
    return '$safeTitle ($safeReal)';
  }
  return safeTitle;
}
