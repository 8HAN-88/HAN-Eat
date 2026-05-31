import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/config/dotenv_safe.dart';
import '../models/analysis_mode.dart';
import '../models/recipe.dart';
import '../models/recipe_model.dart';
import 'api_service.dart';

class RecipeApiService {
  static final _base = 'https://api.spoonacular.com';

  static String? get _apiKey => dotenvString('SPOONACULAR_API_KEY');

  static bool get _useBackendOnly =>
      kReleaseMode || _apiKey == null || _apiKey!.isEmpty;

  static RecipeModel _fromApiRecipe(Recipe r) {
    final stepTexts = r.steps
        .map((s) => (s['step'] as String?)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return RecipeModel(
      id: r.id.toString(),
      title: r.title,
      cookTime: 30,
      ingredients: r.ingredients,
      steps: stepTexts,
      image: r.image ?? r.sourceImage,
      updatedAt: DateTime.now(),
      calories: r.calories?.toDouble(),
      proteinG: r.nutrientGrams('protein'),
      carbsG: r.nutrientGrams('carbohydrates'),
      fatG: r.nutrientGrams('fat'),
    );
  }

  static Future<List<RecipeModel>> _searchViaBackend(
    String query, {
    required int number,
  }) async {
    if (query.trim().isEmpty) {
      final rec = await ApiService.fetchRecommendations(limit: number);
      return rec.recipes.map(_fromApiRecipe).toList();
    }
    final list = await ApiService.searchRecipes(
      query,
      mode: AnalysisMode.all,
      language: 'ru',
    );
    return list.take(number).map(_fromApiRecipe).toList();
  }

  static Future<RecipeModel?> _detailsViaBackend(String id) async {
    final numericId = int.tryParse(id);
    if (numericId == null) return null;
    final recipe = await ApiService.getRecipeById(numericId, language: 'ru');
    if (recipe == null) return null;
    return _fromApiRecipe(recipe);
  }

  // Search recipes by query. Returns List<RecipeModel>.
  static Future<List<RecipeModel>> searchRecipes(String query,
      {int number = 10}) async {
    if (_useBackendOnly) {
      try {
        return await _searchViaBackend(query, number: number);
      } catch (e) {
        if (kDebugMode) debugPrint('RecipeApiService backend search: $e');
        return [];
      }
    }

    final uri =
        Uri.parse('$_base/recipes/complexSearch').replace(queryParameters: {
      'query': query,
      'addRecipeInformation': 'true',
      'number': number.toString(),
      'apiKey': _apiKey!,
    });

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Recipe API error: ${res.statusCode} ${res.body}');
        }
        return [];
      }
      final Map<String, dynamic> jsonBody =
          json.decode(res.body) as Map<String, dynamic>;
      final List<dynamic> results = jsonBody['results'] as List<dynamic>? ?? [];
      final now = DateTime.now();
      final out = results.map((item) {
        final m = item as Map<String, dynamic>;
        final id = (m['id'] ?? '').toString();
        final title = m['title'] as String? ?? '';
        final cookTime = (m['readyInMinutes'] is int)
            ? (m['readyInMinutes'] as int)
            : (m['readyInMinutes'] != null
                ? int.tryParse(m['readyInMinutes'].toString()) ?? 0
                : 0);
        final image = m['image'] as String?;
        final List<String> ingredients = [];
        if (m['extendedIngredients'] is List) {
          for (final ing in (m['extendedIngredients'] as List)) {
            try {
              final Map<String, dynamic> im = ing as Map<String, dynamic>;
              ingredients.add(im['originalString'] as String? ??
                  im['name'] as String? ??
                  '');
            } catch (_) {}
          }
        }
        final List<String> steps = [];
        if (m['analyzedInstructions'] is List) {
          try {
            final instr = (m['analyzedInstructions'] as List).isNotEmpty
                ? (m['analyzedInstructions'] as List).first
                : null;
            if (instr is Map && instr['steps'] is List) {
              for (final st in instr['steps'] as List) {
                try {
                  final Map<String, dynamic> sm = st as Map<String, dynamic>;
                  steps.add(sm['step'] as String? ?? '');
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
        return RecipeModel(
          id: id,
          title: title,
          cookTime: cookTime,
          ingredients: ingredients,
          steps: steps,
          image: image,
          updatedAt: now,
        );
      }).toList();
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('RecipeApiService exception: $e');
      return [];
    }
  }

  static Future<RecipeModel?> getRecipeDetails(String id) async {
    if (_useBackendOnly) {
      try {
        return await _detailsViaBackend(id);
      } catch (e) {
        if (kDebugMode) debugPrint('RecipeApiService backend details: $e');
        return null;
      }
    }

    if (_apiKey == null || _apiKey!.isEmpty) {
      if (kDebugMode) debugPrint('SPOONACULAR_API_KEY not set');
      return null;
    }
    final uri =
        Uri.parse('$_base/recipes/$id/information').replace(queryParameters: {
      'includeNutrition': 'true',
      'apiKey': _apiKey!,
    });

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Recipe details API error: ${res.statusCode} ${res.body}');
        }
        return null;
      }
      final Map<String, dynamic> m =
          json.decode(res.body) as Map<String, dynamic>;

      final title = m['title'] as String? ?? '';
      final cookTime = (m['readyInMinutes'] is int)
          ? (m['readyInMinutes'] as int)
          : (m['readyInMinutes'] != null
              ? int.tryParse(m['readyInMinutes'].toString()) ?? 0
              : 0);
      final image = m['image'] as String?;

      final List<String> ingredients = [];
      if (m['extendedIngredients'] is List) {
        for (final ing in (m['extendedIngredients'] as List)) {
          try {
            final Map<String, dynamic> im = ing as Map<String, dynamic>;
            ingredients.add(
                im['originalString'] as String? ?? im['name'] as String? ?? '');
          } catch (_) {}
        }
      }

      final List<String> steps = [];
      if (m['analyzedInstructions'] is List) {
        try {
          final instrList = (m['analyzedInstructions'] as List);
          if (instrList.isNotEmpty) {
            final firstInstr = instrList.first;
            if (firstInstr is Map && firstInstr['steps'] is List) {
              for (final st in firstInstr['steps'] as List) {
                try {
                  final Map<String, dynamic> sm = st as Map<String, dynamic>;
                  final stepText = sm['step'] as String? ?? '';
                  if (stepText.isNotEmpty) steps.add(stepText);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
      if (steps.isEmpty && m['instructions'] is String) {
        final instr = (m['instructions'] as String).trim();
        if (instr.isNotEmpty) {
          final parts = instr.split(RegExp(r'\. |\n'));
          steps.addAll(
              parts.where((p) => p.trim().isNotEmpty).map((s) => s.trim()));
        }
      }

      double? calories;
      double? proteinG;
      double? carbsG;
      double? fatG;
      final nut = m['nutrition'];
      if (nut is Map && nut['nutrients'] is List) {
        for (final raw in nut['nutrients'] as List<dynamic>) {
          if (raw is! Map) continue;
          final nm = Map<String, dynamic>.from(raw);
          final name = '${nm['name']}'.toLowerCase();
          final amt = nm['amount'];
          final v = amt is num ? amt.toDouble() : double.tryParse('$amt');
          if (v == null) continue;
          if (name == 'calories') {
            calories = v;
          } else if (name == 'protein') {
            proteinG = v;
          } else if (name == 'carbohydrates') {
            carbsG = v;
          } else if (name == 'fat') {
            fatG = v;
          }
        }
      }

      final now = DateTime.now();
      return RecipeModel(
        id: id,
        title: title,
        cookTime: cookTime,
        ingredients: ingredients,
        steps: steps,
        image: image,
        updatedAt: now,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('getRecipeDetails exception: $e');
      return null;
    }
  }
}
