import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe_category.dart';

class CategoryService {
  static CategoryService? _instance;
  static CategoryService get instance {
    if (_instance == null) {
      throw Exception(
          'CategoryService not initialized. Call CategoryService.init() first.');
    }
    return _instance!;
  }

  static const String _boxName = 'category_filters';
  static const String _prefsKey = 'category_filters';
  late final Box _box;

  final ValueNotifier<List<CategoryFilter>> filters = ValueNotifier([]);

  CategoryService._internal(this._box) {
    _loadFilters();
  }

  static Future<void> init() async {
    if (_instance != null) {
      try {
        await _instance!._disposeInternal();
      } catch (_) {}
    }
    final box = await Hive.openBox(_boxName);
    _instance = CategoryService._internal(box);
  }

  void _loadFilters() {
    final prefs = SharedPreferences.getInstance();
    prefs.then((p) {
      final jsonString = p.getString(_prefsKey);
      if (jsonString != null) {
        try {
          final List<dynamic> jsonList = json.decode(jsonString);
          filters.value = jsonList
              .map((j) => CategoryFilter.fromJson(j as Map<String, dynamic>))
              .toList();
          return;
        } catch (e) {
          if (kDebugMode) debugPrint('Error loading category filters: $e');
        }
      }
      // Создаем фильтры по умолчанию
      _createDefaultFilters();
    });
  }

  void _createDefaultFilters() {
    filters.value = RecipeCategory.values
        .map((cat) => CategoryFilter(
              category: cat,
              isActive: false,
              priority: cat.index,
            ))
        .toList();
    _saveFilters();
  }

  void _saveFilters() {
    final jsonList = filters.value.map((f) => f.toJson()).toList();
    final jsonString = json.encode(jsonList);
    SharedPreferences.getInstance().then((p) {
      p.setString(_prefsKey, jsonString);
    });
  }

  void toggleCategory(RecipeCategory category, bool isActive) {
    final updated = filters.value.map((f) {
      if (f.category == category) {
        return f.copyWith(isActive: isActive);
      }
      return f;
    }).toList();
    filters.value = updated;
    _saveFilters();
  }

  bool isCategoryActive(RecipeCategory category) {
    return filters.value
        .firstWhere(
          (f) => f.category == category,
          orElse: () => CategoryFilter(category: category, isActive: false),
        )
        .isActive;
  }

  List<RecipeCategory> getActiveCategories() {
    return filters.value
        .where((f) => f.isActive)
        .map((f) => f.category)
        .toList();
  }

  List<RecipeCategory> getCategoriesByType(CategoryType type) {
    return RecipeCategory.values.where((cat) => cat.type == type).toList();
  }

  List<String> getSpoonacularTagsForActiveCategories() {
    return getActiveCategories().map((cat) => cat.spoonacularTag).toList();
  }

  void resetAllFilters() {
    filters.value = filters.value.map((f) => f.copyWith(isActive: false)).toList();
    _saveFilters();
  }

  Future<void> _disposeInternal() async {
    try {
      await _box.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _disposeInternal();
    filters.dispose();
    _instance = null;
  }
}

