/// Утилита для форматирования чисел
/// Например: 1000 -> "1к", 1100 -> "1,1к", 1500 -> "1,5к"
class NumberFormatter {
  /// Форматирует число в компактный вид
  /// Если число >= 1000, показывает в формате "1к", "1,1к" и т.д.
  static String formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 10000) {
      // Для чисел от 1000 до 9999 показываем с одной десятичной
      final thousands = count / 1000;
      // Если число кратно 1000, показываем без десятичной
      if (count % 1000 == 0) {
        return '${thousands.toInt()}к';
      }
      // Округляем до одной десятичной и заменяем точку на запятую
      final formatted = (thousands * 10).round() / 10;
      return '${formatted.toString().replaceAll('.', ',')}к';
    } else if (count < 1000000) {
      // Для чисел от 10000 до 999999 показываем как "10к", "100к" и т.д.
      final thousands = (count / 1000).round();
      return '$thousandsк';
    } else {
      // Для чисел >= 1000000 показываем как "1м", "1,1м" и т.д.
      final millions = count / 1000000;
      if (count % 1000000 == 0) {
        return '${millions.toInt()}м';
      }
      final formatted = (millions * 10).round() / 10;
      return '${formatted.toString().replaceAll('.', ',')}м';
    }
  }
}

