/// Online when the last mark is within three minutes, including a small
/// future skew. A timestamp hours ahead is not "в сети".
bool isRecentlyOnline(DateTime? lastSeen, {DateTime? now}) {
  if (lastSeen == null) return false;
  final diff = (now ?? DateTime.now()).difference(lastSeen.toLocal()).abs();
  return diff < const Duration(minutes: 3);
}

String formatLastSeen(DateTime? lastSeen, {DateTime? now}) {
  if (lastSeen == null) return '';
  final clock = now ?? DateTime.now();
  final local = lastSeen.toLocal();
  if (isRecentlyOnline(lastSeen, now: clock)) return 'в сети';
  var diff = clock.difference(local);
  if (diff.isNegative) diff = Duration.zero;
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    if (m < 1) return 'был(а) только что';
    return 'был(а) $m ${_minutesLabel(m)} назад';
  }
  final startToday = DateTime(clock.year, clock.month, clock.day);
  final startThen = DateTime(local.year, local.month, local.day);
  final days = startToday.difference(startThen).inDays;
  if (days <= 0) {
    final h = diff.inHours;
    return 'был(а) $h ${_hoursLabel(h)} назад';
  }
  if (days == 1) return 'был(а) вчера в ${_hm(local)}';
  if (days < 7) return 'был(а) $days ${_daysLabel(days)} назад';
  return 'был(а) давно';
}

String _hm(DateTime local) {
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _minutesLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'минут';
  if (mod10 == 1) return 'минуту';
  if (mod10 >= 2 && mod10 <= 4) return 'минуты';
  return 'минут';
}

String _hoursLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'часов';
  if (mod10 == 1) return 'час';
  if (mod10 >= 2 && mod10 <= 4) return 'часа';
  return 'часов';
}

String _daysLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'дней';
  if (mod10 == 1) return 'день';
  if (mod10 >= 2 && mod10 <= 4) return 'дня';
  return 'дней';
}
