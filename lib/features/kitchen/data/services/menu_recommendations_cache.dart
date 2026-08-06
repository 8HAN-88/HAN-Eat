import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import 'package:han_eat/services/api_service.dart';

/// Дисковый кэш рекомендаций меню для мгновенного открытия вкладки.
class MenuRecommendationsCache {
  MenuRecommendationsCache._();

  static const _key = 'menu_recommendations_cache_v1';
  static const payloadVersion = 15;

  static RecommendationsResult? _memory;

  static RecommendationsResult? peek() => _memory;

  static Future<void> warmUp() async {
    if (_memory != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if ((map['payload_version'] as int? ?? 0) != payloadVersion) return;
      _memory = _fromStored(map);
    } catch (e) {
      if (kDebugMode) debugPrint('MenuRecommendationsCache.warmUp: $e');
    }
  }

  static Future<void> save(RecommendationsResult result) async {
    if (result.recipes.length < 3) return;
    _memory = result;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'payload_version': payloadVersion,
          'saved_at': DateTime.now().millisecondsSinceEpoch,
          'recipes': result.recipes.map((r) => r.toJson()).toList(),
          'spoonacular_quota_exhausted': result.spoonacularQuotaExhausted,
          'viewer_is_plus': result.viewerIsPlus,
          'suggest_plus_upgrade': result.suggestPlusUpgrade,
          'recipe_translation_enabled': result.recipeTranslationEnabled,
          'recipe_translation_requires_ai': result.recipeTranslationRequiresAi,
          'recipe_translation_language': result.recipeTranslationLanguage,
          'recipe_translation_api_supported':
              result.recipeTranslationApiSupported,
        }),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('MenuRecommendationsCache.save: $e');
    }
  }

  static RecommendationsResult _fromStored(Map<String, dynamic> map) {
    final list = map['recipes'] as List<dynamic>? ?? const [];
    return RecommendationsResult(
      recipes: list
          .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
          .toList(),
      spoonacularQuotaExhausted:
          map['spoonacular_quota_exhausted'] == true,
      viewerIsPlus: map['viewer_is_plus'] == true,
      suggestPlusUpgrade: map['suggest_plus_upgrade'] == true,
      recipeTranslationEnabled: map['recipe_translation_enabled'] == true,
      recipeTranslationRequiresAi:
          map['recipe_translation_requires_ai'] == true,
      recipeTranslationLanguage:
          map['recipe_translation_language'] as String?,
      recipeTranslationApiSupported:
          map['recipe_translation_api_supported'] == true,
    );
  }
}
