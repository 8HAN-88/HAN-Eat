/// Форматирование E.164 для отображения (как в Telegram).
String formatPhoneForDisplay(String e164) {
  final digits = e164.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('7')) {
    return '+7 ${digits.substring(1, 4)} ${digits.substring(4, 7)} '
        '${digits.substring(7, 9)} ${digits.substring(9)}';
  }
  if (digits.length == 11 && digits.startsWith('1')) {
    return '+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-'
        '${digits.substring(7)}';
  }
  if (e164.startsWith('+')) return e164;
  return '+$digits';
}
