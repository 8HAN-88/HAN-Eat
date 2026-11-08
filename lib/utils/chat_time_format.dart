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
