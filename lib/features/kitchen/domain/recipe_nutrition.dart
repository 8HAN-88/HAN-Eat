// Разбор БЖУ из Recipe.nutrition (ключи API + массив nutrients Spoonacular).

bool _isMainFatNutrientName(String s) {
  if (!s.contains('fat')) return false;
  if (s.contains('saturated')) return false;
  if (s.contains('trans')) return false;
  if (s.contains('monounsaturated')) return false;
  if (s.contains('polyunsaturated')) return false;
  return true;
}

double? _readNumeric(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final m = RegExp(r'(\d+\.?\d*)').firstMatch(v);
    if (m != null) return double.tryParse(m.group(1)!);
  }
  return null;
}

/// Общие жиры (г): прямые ключи или строка `nutrients` с именем вроде «Fat» / «Total Fat».
double? parseNutritionFat(Map<String, dynamic>? nutrition) {
  if (nutrition == null) return null;

  final direct = nutrition['fat'] ??
      nutrition['fats'] ??
      nutrition['Fat'] ??
      nutrition['Fats'];
  final fromKey = _readNumeric(direct);
  if (fromKey != null) return fromKey;

  final nutrients = nutrition['nutrients'];
  if (nutrients is! List) return null;

  for (final n in nutrients) {
    if (n is! Map) continue;
    final name = (n['name']?.toString() ?? '').toLowerCase();
    final title = (n['title']?.toString() ?? '').toLowerCase();
    final searchName = title.isNotEmpty ? title : name;
    if (!_isMainFatNutrientName(searchName)) continue;
    final amount = n['amount'];
    final parsed = _readNumeric(amount);
    if (parsed != null) return parsed;
  }
  return null;
}
