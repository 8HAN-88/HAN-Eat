import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/recipe_model.dart';

class RecipeApiService {
  static final _base = 'https://api.spoonacular.com';

  static String? get _apiKey => dotenv.env['SPOONACULAR_API_KEY'];

  // Search recipes by query. Returns List<RecipeModel>.
  static Future<List<RecipeModel>> searchRecipes(String query,
      {int number = 10}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      if (kDebugMode) debugPrint('SPOONACULAR_API_KEY not set');
      return [];
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
        if (kDebugMode)
          debugPrint('Recipe API error: ${res.statusCode} ${res.body}');
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
        // ingredients: try extendedIngredients -> originalString
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
        // steps: try analyzedInstructions[0].steps[].step
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

  // Get detailed recipe information by id
  static Future<RecipeModel?> getRecipeDetails(String id) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      if (kDebugMode) debugPrint('SPOONACULAR_API_KEY not set');
      return null;
    }
    final uri =
        Uri.parse('$_base/recipes/$id/information').replace(queryParameters: {
      'includeNutrition': 'false',
      'apiKey': _apiKey!,
    });

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        if (kDebugMode)
          debugPrint('Recipe details API error: ${res.statusCode} ${res.body}');
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
      // Try analyzedInstructions first
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
      // Fallback to 'instructions' string (may contain HTML)
      if (steps.isEmpty && m['instructions'] is String) {
        final instr = (m['instructions'] as String).trim();
        if (instr.isNotEmpty) {
          // naive split by sentences/newlines
          final parts = instr.split(RegExp(r'\. |\n'));
          steps.addAll(
              parts.where((p) => p.trim().isNotEmpty).map((s) => s.trim()));
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
      );
    } catch (e) {
      if (kDebugMode) debugPrint('getRecipeDetails exception: $e');
      return null;
    }
  }
}
