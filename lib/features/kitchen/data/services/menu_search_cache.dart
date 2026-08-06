import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';
import 'package:han_eat/services/api_service.dart';

/// Кэш результатов поиска рецептов в меню (последние запросы).
class MenuSearchCache {
  MenuSearchCache._();

  static const _key = 'menu_search_cache_v1';
  static const _maxEntries = 20;

  static final Map<String, SearchRecipesResult> _memory = {};

  static String buildKey({
    required String query,
    required String mode,
    required String language,
    String? tags,
    int? maxReadyTime,
  }) {
    return [
      mode,
      language,
      query.trim().toLowerCase(),
      tags ?? '',
      maxReadyTime?.toString() ?? '',
    ].join('|');
  }

  static SearchRecipesResult? peek(String cacheKey) => _memory[cacheKey];

  static Future<void> warmUp() async {
    if (_memory.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final payload = entry.value;
        if (payload is! Map<String, dynamic>) continue;
        _memory[entry.key] = _fromStored(payload);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MenuSearchCache.warmUp: $e');
    }
  }

  static Future<void> save(String cacheKey, SearchRecipesResult result) async {
    if (result.recipes.isEmpty) return;
    _memory[cacheKey] = result;
    while (_memory.length > _maxEntries) {
      _memory.remove(_memory.keys.first);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, dynamic>{
        for (final e in _memory.entries) e.key: _toStored(e.value),
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (e) {
      if (kDebugMode) debugPrint('MenuSearchCache.save: $e');
    }
  }

  static Map<String, dynamic> _toStored(SearchRecipesResult result) {
    return {
      'recipes': result.recipes.map((r) => r.toJson()).toList(),
      'recipe_translation_enabled': result.recipeTranslationEnabled,
      'recipe_translation_requires_ai': result.recipeTranslationRequiresAi,
      'recipe_translation_api_supported': result.recipeTranslationApiSupported,
      'source': result.source,
    };
  }

  static SearchRecipesResult _fromStored(Map<String, dynamic> map) {
    final list = map['recipes'] as List<dynamic>? ?? const [];
    return SearchRecipesResult(
      recipes: list
          .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
          .toList(),
      recipeTranslationEnabled: map['recipe_translation_enabled'] == true,
      recipeTranslationRequiresAi: map['recipe_translation_requires_ai'] == true,
      recipeTranslationApiSupported:
          map['recipe_translation_api_supported'] == true,
      source: map['source'] as String?,
    );
  }
}
