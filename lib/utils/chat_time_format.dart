import 'package:intl/intl.dart';

/// Clock for today, `dd.MM` for any other calendar day.
///
/// [now] is for tests. A 24-hour [Duration.inDays] check hid yesterday's
/// evening messages as a bare clock after midnight.
String formatChatMessageTime(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final sameDay = local.year == clock.year &&
      local.month == clock.month &&
      local.day == clock.day;
  if (sameDay) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}

/// «только что», «N мин назад», «вчера». Future times are a clock or a date,
/// never a negative «-3 ч назад».
String formatRelativeTime(
  DateTime date, {
  DateTime? now,
  bool withYear = false,
}) {
  final local = date.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final diff = clock.difference(local);
  if (diff.isNegative) {
    final sameDay = local.year == clock.year &&
        local.month == clock.month &&
        local.day == clock.day;
    if (sameDay) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return _formatRelativeDay(local, withYear: withYear);
  }
  final sameDay = local.year == clock.year &&
      local.month == clock.month &&
      local.day == clock.day;
  if (sameDay) {
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    return '${diff.inHours} ч назад';
  }
  final startToday = DateTime(clock.year, clock.month, clock.day);
  final startThen = DateTime(local.year, local.month, local.day);
  final days = startToday.difference(startThen).inDays;
  if (days == 1) return 'вчера';
  if (days > 1 && days < 7) return '$days дн назад';
  return _formatRelativeDay(local, withYear: withYear);
}

/// 21:00 today, or 21:00 tomorrow once that slot is less than 30 seconds away.
/// The label follows that calendar day, so after 21:00 it is not
/// «Сегодня вечером».
({DateTime at, String label}) scheduleEveningPreset(DateTime now) {
  final clock = now.toLocal();
  var at = DateTime(clock.year, clock.month, clock.day, 21);
  if (!at.isAfter(clock.add(const Duration(seconds: 30)))) {
    at = DateTime(clock.year, clock.month, clock.day + 1, 21);
  }
  final sameDay =
      at.year == clock.year && at.month == clock.month && at.day == clock.day;
  return (
    at: at,
    label: sameDay ? 'Сегодня вечером' : 'Завтра вечером',
  );
}

String _formatRelativeDay(DateTime local, {required bool withYear}) {
  final pattern = withYear ? 'd MMM yyyy' : 'd MMM';
  try {
    return DateFormat(pattern, 'ru').format(local);
  } catch (_) {
    return DateFormat(pattern).format(local);
  }
}
