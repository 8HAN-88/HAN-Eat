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
