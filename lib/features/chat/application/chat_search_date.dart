// Helpers for Telegram-like date filter in in-chat search.

bool messageMatchesSearchDate(DateTime createdAt, DateTime? day) {
  if (day == null) return true;
  final local = createdAt.toLocal();
  final d = DateTime(day.year, day.month, day.day);
  return local.year == d.year && local.month == d.month && local.day == d.day;
}

/// Inclusive calendar-day bounds as `YYYY-MM-DD` query params.
({String dateFrom, String dateTo}) searchDateQueryBounds(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  String pad(int n) => n.toString().padLeft(2, '0');
  final key = '${d.year}-${pad(d.month)}-${pad(d.day)}';
  return (dateFrom: key, dateTo: key);
}

String searchDateChipLabel(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final pad = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$pad.$mon.${d.year}';
}
