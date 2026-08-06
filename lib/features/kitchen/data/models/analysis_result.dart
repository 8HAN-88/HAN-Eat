import 'recipe.dart';

num? _parseNutritionValue(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final s = v
        .trim()
        .replaceAll(
          RegExp(r'\s*(g|mg|kcal|ккал|г|мг)\s*$', caseSensitive: false),
          '',
        )
        .replaceAll(',', '.')
        .trim();
    return num.tryParse(s);
  }
  return null;
}

Map<String, dynamic>? _normalizeNutrition(Map<String, dynamic> json) {
  final rawNutrition = json['nutrition'];
  final out = <String, dynamic>{};

  void put(String key, dynamic value) {
    final n = _parseNutritionValue(value);
    if (n == null) return;
    final k = key.toString().toLowerCase();
    if (k == 'proteins' || k == 'protein_g') {
      out['protein'] = n;
    } else if (k == 'fats' || k == 'fat_g') {
      out['fat'] = n;
    } else if (k == 'carb' ||
        k == 'carbs' ||
        k == 'carbs_g' ||
        k == 'carbohydrates_g') {
      out['carbohydrates'] = n;
    } else if (k == 'fiber_g') {
      out['fiber'] = n;
    } else {
      out[k] = n;
    }
  }

  if (rawNutrition is Map) {
    for (final e in rawNutrition.entries) {
      put(e.key.toString(), e.value);
    }
  }

  for (final key in const [
    'protein',
    'proteins',
    'protein_g',
    'fat',
    'fats',
    'fat_g',
    'carbohydrates',
    'carbs',
    'carb',
    'carbs_g',
    'carbohydrates_g',
    'fiber',
    'fiber_g',
  ]) {
    put(key, json[key]);
  }

  return out.isEmpty ? null : out;
}

class AnalysisResult {
  AnalysisResult({
    required this.label,
    required this.translatedLabel,
    required this.confidence,
    required this.calories,
    required this.nutrition,
    required this.recipes,
    this.portionGrams,
  });

  final String? label;
  final String? translatedLabel;
  final double? confidence;
  final num? calories;
  final Map<String, dynamic>? nutrition;
  final List<Recipe> recipes;
  /// Оценка веса порции на фото (г); КБЖУ — на эту порцию.
  final num? portionGrams;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final recipesJson = json['recipes'] as List<dynamic>? ?? [];
    final nutrition = _normalizeNutrition(json);
    return AnalysisResult(
      label: json['label'] as String?,
      translatedLabel:
          json['translated_label'] as String? ?? json['label'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      calories: _parseNutritionValue(json['calories']),
      nutrition: nutrition,
      recipes: recipesJson
          .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
          .toList(),
      portionGrams: _parseNutritionValue(
        json['portion_grams'] ?? json['portionGrams'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'translated_label': translatedLabel,
        'confidence': confidence,
        'calories': calories,
        'nutrition': nutrition,
        'portion_grams': portionGrams,
        'recipes': recipes.map((r) => r.toJson()).toList(),
      };
}

