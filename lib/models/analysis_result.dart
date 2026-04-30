import 'recipe.dart';

num? _parseNutritionValue(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final s = v.trim().replaceAll(RegExp(r'\s*(g|mg|kcal|ккал|г|мг)\s*$', caseSensitive: false), '').trim();
    return num.tryParse(s);
  }
  return null;
}

class AnalysisResult {
  AnalysisResult({
    required this.label,
    required this.translatedLabel,
    required this.confidence,
    required this.calories,
    required this.nutrition,
    required this.recipes,
  });

  final String? label;
  final String? translatedLabel;
  final double? confidence;
  final num? calories;
  final Map<String, dynamic>? nutrition;
  final List<Recipe> recipes;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final recipesJson = json['recipes'] as List<dynamic>? ?? [];
    final rawNutrition = json['nutrition'] as Map<String, dynamic>?;
    // Нормализуем ключи и значения: protein/proteins -> protein, значения парсим в num
    Map<String, dynamic>? nutrition;
    if (rawNutrition != null && rawNutrition.isNotEmpty) {
      nutrition = {};
      for (final e in rawNutrition.entries) {
        if (e.value == null) continue;
        final n = _parseNutritionValue(e.value);
        if (n == null) continue;
        final k = e.key.toString().toLowerCase();
        String normKey = e.key.toString();
        if (k == 'proteins') normKey = 'protein';
        else if (k == 'fats') normKey = 'fat';
        else if (k == 'carb' || k == 'carbs') normKey = 'carbohydrates';
        nutrition[normKey] = n;
      }
    }
    return AnalysisResult(
      label: json['label'] as String?,
      translatedLabel: json['translated_label'] as String? ?? json['label'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      calories: _parseNutritionValue(json['calories']),
      nutrition: nutrition,
      recipes: recipesJson
          .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

