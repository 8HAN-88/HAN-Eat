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

/// Local calendar day as `YYYY-MM-DD`. Sent with [searchTzOffsetMinutes]
/// so the server can place that day on the UTC clock messages are stored in.
String searchDayKey(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

/// `DateTime.timeZoneOffset` in minutes. Moscow is 180.
int searchTzOffsetMinutes() => DateTime.now().timeZoneOffset.inMinutes;
