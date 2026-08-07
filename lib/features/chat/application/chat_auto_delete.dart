// Helpers for conversation-level auto-delete TTL (Telegram-style).

DateTime? messageAutoDeleteExpiresAt(
  DateTime createdAt,
  int autoDeleteSeconds,
) {
  if (autoDeleteSeconds <= 0) return null;
  return createdAt.toUtc().add(Duration(seconds: autoDeleteSeconds));
}

bool isMessageAutoDeleted(
  DateTime createdAt,
  int autoDeleteSeconds, {
  DateTime? now,
}) {
  final expires = messageAutoDeleteExpiresAt(createdAt, autoDeleteSeconds);
  if (expires == null) return false;
  return !(now ?? DateTime.now()).toUtc().isBefore(expires);
}

/// Compact remaining label for bubble meta (e.g. `5м`, `2ч`, `3д`, `12с`).
String formatAutoDeleteRemaining(
  DateTime createdAt,
  int autoDeleteSeconds, {
  DateTime? now,
}) {
  final expires = messageAutoDeleteExpiresAt(createdAt, autoDeleteSeconds);
  if (expires == null) return '';
  final left = expires.difference((now ?? DateTime.now()).toUtc());
  if (left.inSeconds <= 0) return '0с';
  if (left.inDays >= 1) return '${left.inDays}д';
  if (left.inHours >= 1) return '${left.inHours}ч';
  if (left.inMinutes >= 1) return '${left.inMinutes}м';
  return '${left.inSeconds}с';
}
