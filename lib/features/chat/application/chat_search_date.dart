import '../../../utils/api_datetime.dart';

// Helpers for Telegram-like date filter in in-chat search.

bool messageMatchesSearchDate(DateTime createdAt, DateTime? day) {
  if (day == null) return true;
  final local = createdAt.toLocal();
  final d = DateTime(day.year, day.month, day.day);
  return local.year == d.year && local.month == d.month && local.day == d.day;
}

/// Inclusive bounds of the local calendar day, as UTC instants.
({String dateFrom, String dateTo}) searchDateQueryBounds(DateTime day) {
  return (
    dateFrom: searchDayBoundIso(day, end: false),
    dateTo: searchDayBoundIso(day, end: true),
  );
}

String searchDateChipLabel(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final pad = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$pad.$mon.${d.year}';
}
