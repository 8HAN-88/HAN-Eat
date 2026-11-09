/// API timestamps are UTC. Naive strings have no `Z`, and Dart would
/// otherwise read them as the phone's local clock.
DateTime? parseApiDateTime(Object? raw) {
  if (raw is DateTime) return raw.toLocal();
  if (raw is! String) return null;
  var trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final hasZone = trimmed.endsWith('Z') ||
      trimmed.endsWith('z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(trimmed) ||
      RegExp(r'[+-]\d{4}$').hasMatch(trimmed);
  final hasTime = trimmed.contains('T') || trimmed.contains(' ');
  if (!hasZone && hasTime) {
    trimmed = '${trimmed}Z';
  }
  return DateTime.tryParse(trimmed)?.toLocal();
}

/// Inclusive UTC instant for the start or end of [day]'s local calendar day.
///
/// Search stores naive UTC. A bare `YYYY-MM-DD` is that UTC day, so in
/// Moscow the first three hours of the picked day never match.
String searchDayBoundIso(DateTime day, {required bool end}) {
  final local = end
      ? DateTime(day.year, day.month, day.day, 23, 59, 59, 999, 999)
      : DateTime(day.year, day.month, day.day);
  return local.toUtc().toIso8601String();
}
