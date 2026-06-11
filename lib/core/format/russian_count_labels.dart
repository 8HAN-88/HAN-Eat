/// Склонение «подписчик» для счётчиков канала.
String formatChannelMembersCount(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return '$n подписчиков';
  if (mod10 == 1) return '$n подписчик';
  if (mod10 >= 2 && mod10 <= 4) return '$n подписчика';
  return '$n подписчиков';
}
