import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_mode.dart';
import '../models/analysis_result.dart';
import '../models/recipe.dart';
import 'api_service.dart';
import 'server_config.dart';

/// Анализ фото блюда через GPT-4 Vision. Возвращает название блюда, калории, БЖУ и т.д.,
/// затем подгружает похожие рецепты через поиск (с картинками и переводом).
class GptAnalyzeService {
  static String? get _apiKey {
    if (kIsWeb) return null; // на web .env не загружается
    try {
      return dotenv.env['OPENAI_API_KEY'];
    } catch (_) {
      return null; // NotInitializedError если dotenv ещё не загружен
    }
  }

  static bool get isAvailable => _apiKey != null && _apiKey!.isNotEmpty;

  static const _visionUrl = 'https://api.openai.com/v1/chat/completions';

  /// Парсит число из ответа GPT (может прийти как num или строка "25" / "25 g").
  static num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) {
      final s = v.trim().replaceAll(RegExp(r'\s*(g|mg|kcal|ккал|г|мг)\s*$', caseSensitive: false), '').trim();
      return num.tryParse(s);
    }
    return null;
  }

  /// Язык для ответа GPT (ru, en, es, de, fr).
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

  /// Анализировать фото через GPT-4 Vision и подгрузить похожие рецепты (с картинками и языком).
  static Future<AnalysisResult> analyzePhoto(
    Uint8List imageBytes, {
    required String language,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY не задан. Добавьте в .env: OPENAI_API_KEY=sk-...');
    }

    final lang = _langName(language);
    final base64Image = base64Encode(imageBytes);

    final prompt = '''
Analyze this food dish photo. You MUST reply only in $lang. The dish_name MUST be written exclusively in $lang (e.g. if $lang is Russian, write the dish name in Russian).
Reply with a single JSON object, no markdown, no extra text:
{
  "dish_name": "name of the dish in $lang only",
  "calories": number (estimated kcal, digits only, no units),
  "confidence": number between 0 and 1,
  "nutrition": {
    "protein": number (grams, digits only),
    "fat": number (grams, digits only),
    "carbohydrates": number (grams, digits only),
    "fiber": number or null,
    "sugar": number or null,
    "sodium": number or null
  }
}
Rules: dish_name must be in $lang. All numeric values must be plain numbers (no strings, no units like "g" or "kcal"). If unknown use null. Use only the keys above.
''';

    final body = {
      'model': 'gpt-4o',
      'max_tokens': 500,
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

    final resp = await http.post(
      Uri.parse(_visionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      final err = resp.body;
      if (kDebugMode) debugPrint('OpenAI error: $err');
      throw Exception('Ошибка анализа: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = (data['choices'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>()
        .firstOrNull?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception('Пустой ответ от GPT');
    }

    // Убираем возможные markdown-обёртки
    String jsonStr = content.trim();
    if (jsonStr.startsWith('```')) {
      jsonStr = jsonStr.replaceFirst(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
    }
    final analysisJson = jsonDecode(jsonStr) as Map<String, dynamic>;

    final dishName = analysisJson['dish_name'] as String? ?? 'Блюдо';
    final calories = _parseNum(analysisJson['calories']);
    final confidence = (analysisJson['confidence'] as num?)?.toDouble();
    final nutritionRaw = analysisJson['nutrition'];
    Map<String, dynamic>? nutrition;
    if (nutritionRaw is Map) {
      nutrition = {};
      for (final e in (nutritionRaw as Map).entries) {
        if (e.value == null) continue;
        final num? n = _parseNum(e.value);
        if (n == null) continue;
        final k = (e.key as String).toLowerCase();
        final key = k == 'carbs' || k == 'carb' ? 'carbohydrates' : k;
        nutrition[key] = n;
      }
    }

    // Похожие рецепты — через поиск по названию блюда (приходят с картинками и переводом с бэкенда)
    List<Recipe> recipes = [];
    try {
      recipes = await ApiService.searchRecipes(
        dishName,
        mode: AnalysisMode.all,
        language: language,
      );
      if (recipes.length > 10) {
        recipes = recipes.take(10).toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Search recipes for similar failed: $e');
    }

    return AnalysisResult(
      label: dishName,
      translatedLabel: dishName,
      confidence: confidence,
      calories: calories,
      nutrition: nutrition,
      recipes: recipes,
    );
  }
}
