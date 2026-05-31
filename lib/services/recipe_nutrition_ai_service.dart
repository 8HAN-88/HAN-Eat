import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/api_error_parser.dart';
import 'auth_service.dart';
import 'server_config.dart';

class RecipeNutritionResult {
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? confidence;

  const RecipeNutritionResult({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.confidence,
  });

  factory RecipeNutritionResult.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? cal;
    final c = json['calories'];
    if (c is num) cal = c.round();
    if (c is String) cal = int.tryParse(c);

    return RecipeNutritionResult(
      calories: cal,
      proteinG: d(json['protein_g']),
      carbsG: d(json['carbs_g']),
      fatG: d(json['fat_g']),
      fiberG: d(json['fiber_g']),
      confidence: d(json['confidence']),
    );
  }
}

class RecipeNutritionAiService {
  static String get _baseUrl => '${ServerConfig.apiBaseUrl}/creator';

  static Future<RecipeNutritionResult> analyzeRecipe({
    required String title,
    List<String> ingredients = const [],
    List<String> steps = const [],
    String? description,
    int servings = 1,
    String language = 'ru',
  }) async {
    final token = await AuthService.getAccessTokenForApi();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final uri = Uri.parse('$_baseUrl/recipes/analyze-nutrition');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'ingredients': ingredients,
        'steps': steps,
        'servings': servings,
        'language': language,
      }),
    );

    if (response.statusCode == 200) {
      return RecipeNutritionResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    final error = jsonDecode(response.body) as Map<String, dynamic>;
    throw apiExceptionFromResponse(
      response.statusCode,
      error,
      fallback: 'Не удалось рассчитать питание',
    );
  }
}
