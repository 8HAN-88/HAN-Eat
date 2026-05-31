/// Парсинг полей питания из текстовых контроллеров.
int? parseIntField(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

double? parseDoubleField(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
