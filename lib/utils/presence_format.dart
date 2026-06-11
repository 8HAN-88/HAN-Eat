String formatLastSeen(DateTime? lastSeen) {
  if (lastSeen == null) return '';
  final local = lastSeen.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 3) return 'в сети';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'был(а) $m ${_minutesLabel(m)} назад';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'был(а) $h ${_hoursLabel(h)} назад';
  }
  if (diff.inDays == 1) return 'был(а) вчера';
  if (diff.inDays < 7) {
    final d = diff.inDays;
    return 'был(а) $d ${_daysLabel(d)} назад';
  }
  return 'был(а) давно';
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
