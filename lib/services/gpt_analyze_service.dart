import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/dotenv_safe.dart';

import '../models/analysis_mode.dart';
import '../models/analysis_result.dart';
import '../models/recipe.dart';
import '../features/menu/scan_recipe_ranking.dart';
import 'api_service.dart';

/// Быстрый анализ фото через GPT-4o-mini (без блокирующего поиска рецептов).
class GptAnalyzeService {
  static String? get _apiKey {
    if (kIsWeb) return null;
    return dotenvString('OPENAI_API_KEY');
  }

  static bool get isAvailable => _apiKey != null && _apiKey!.isNotEmpty;

  /// Дешевле и быстрее gpt-4o-mini; переопределение: OPENAI_FOOD_SCAN_MODEL в .env
  static String get _model =>
      dotenvString('OPENAI_FOOD_SCAN_MODEL') ?? 'gpt-4o-mini';

  static const _visionUrl = 'https://api.openai.com/v1/chat/completions';

  static num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) {
      final s = v
          .trim()
          .replaceAll(
            RegExp(r'\s*(g|mg|kcal|ккал|г|мг)\s*$', caseSensitive: false),
            '',
          )
          .trim();
      return num.tryParse(s);
    }
    return null;
  }

  static String _langName(String code) {
    switch (code.toLowerCase()) {
      case 'ru':
        return 'Russian';
      case 'es':
        return 'Spanish';
      case 'de':
        return 'German';
      case 'fr':
        return 'French';
      case 'en':
      default:
        return 'English';
    }
  }

  /// Только распознавание блюда и КБЖУ (~3–8 с).
  static Future<AnalysisResult> analyzePhotoCore(
    Uint8List imageBytes, {
    required String language,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY не задан');
    }

    final lang = _langName(language);
    final base64Image = base64Encode(imageBytes);

    final prompt = '''
Food photo. Reply in $lang. JSON only.
Pick ONE most likely dish with a specific stable name (not generic "food").
Estimate portion_grams (visible serving on the plate). calories and nutrition must match THAT portion, not per 100g. Round calories to nearest 10.
{"dish_name":"...","portion_grams":number,"calories":number,"confidence":0-1,"nutrition":{"protein":g,"fat":g,"carbohydrates":g,"fiber":g or null,"sugar":g or null,"sodium":mg or null}}
''';

    final body = {
      'model': _model,
      'max_tokens': 220,
      'temperature': 0,
      'seed': 42,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
                'detail': 'low',
              },
            },
          ],
        },
      ],
    };

    final resp = await http
        .post(
          Uri.parse(_visionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 18));

    if (resp.statusCode != 200) {
      throw Exception('Ошибка анализа: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = (data['choices'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>()
        .firstOrNull?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Пустой ответ от GPT');
    }

    var jsonStr = content.trim();
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr
          .replaceFirst(RegExp(r'^```\w*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '');
    }
    final analysisJson = jsonDecode(jsonStr) as Map<String, dynamic>;

    final dishName = analysisJson['dish_name'] as String? ?? 'Блюдо';
    final calories = _parseNum(analysisJson['calories']);
    final confidence = (analysisJson['confidence'] as num?)?.toDouble();
    final nutritionRaw = analysisJson['nutrition'];
    Map<String, dynamic>? nutrition;
    if (nutritionRaw is Map) {
      nutrition = {};
      for (final e in nutritionRaw.entries) {
        if (e.value == null) continue;
        final n = _parseNum(e.value);
        if (n == null) continue;
        final k = (e.key as String).toLowerCase();
        final key = k == 'carbs' || k == 'carb' ? 'carbohydrates' : k;
        nutrition[key] = n;
      }
    }

    return AnalysisResult(
      label: dishName,
      translatedLabel: dishName,
      confidence: confidence,
      calories: calories,
      nutrition: nutrition,
      recipes: const [],
      portionGrams: _parseNum(
        analysisJson['portion_grams'] ?? analysisJson['portionGrams'],
      ),
    );
  }

  /// Похожие рецепты отдельным запросом (после показа блюда).
  static Future<List<Recipe>> fetchSimilarRecipes(
    String dishName, {
    required String language,
  }) async {
    if (dishName.trim().length < 2) return const [];
    try {
      var recipes = await ApiService.searchRecipes(
        dishName,
        mode: AnalysisMode.all,
        language: language,
        timeout: const Duration(seconds: 12),
      );
      if (recipes.length > 6) {
        recipes = recipes.take(6).toList();
      }
      return ScanRecipeRanking.filterForScan(recipes, dishName);
    } catch (e) {
      if (kDebugMode) debugPrint('GPT scan searchRecipes: $e');
      return const [];
    }
  }

  static Future<AnalysisResult> analyzePhoto(
    Uint8List imageBytes, {
    required String language,
  }) async {
    final core = await analyzePhotoCore(
      imageBytes,
      language: language,
    );
    final recipes = await fetchSimilarRecipes(
      core.translatedLabel ?? core.label ?? '',
      language: language,
    );
    return AnalysisResult(
      label: core.label,
      translatedLabel: core.translatedLabel,
      confidence: core.confidence,
      calories: core.calories,
      nutrition: core.nutrition,
      recipes: recipes,
    );
  }
}
