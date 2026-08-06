import 'dart:async';
import 'package:han_eat/core/network/feed_load_helper.dart';
import 'package:han_eat/utils/api_error_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/features/kitchen/data/models/analysis_result.dart';
import 'package:han_eat/features/kitchen/data/models/analysis_mode.dart';
import 'package:han_eat/features/kitchen/data/models/recipe.dart';
import 'package:han_eat/features/kitchen/data/models/recipe_model.dart';
import 'package:han_eat/features/kitchen/data/models/meal_plan.dart';
import 'package:han_eat/features/kitchen/recipe_detail/presentation/detail_page.dart';
import 'package:han_eat/features/kitchen/data/services/ai_scan_image.dart';
import 'package:han_eat/features/kitchen/data/services/scan_result_cache.dart';
import 'package:han_eat/services/api_service.dart';
import 'package:han_eat/services/product_analytics.dart';
import 'package:han_eat/features/subscription/presentation/widgets/subscription_visuals.dart';
import 'package:han_eat/features/subscription/subscription_copy.dart';
import '../scan_recipe_ranking.dart';
import 'package:han_eat/features/kitchen/data/services/gpt_analyze_service.dart';
import 'package:han_eat/core/layout/floating_bottom_padding.dart';
import 'package:han_eat/features/kitchen/ai_scan/application/analysis_mode_controller.dart';
import '../../meal_plan/presentation/add_to_meal_plan_screen.dart';
import '../../meal_plan/presentation/widgets/ai_meal_plan_widgets.dart';
import 'widgets/scan_result_widgets.dart';

/// Локализованные строки для экрана результата сканирования по коду языка.
Map<String, String> _scanResultStrings(String languageCode) {
  final lang = languageCode.toLowerCase();
  switch (lang) {
    case 'en':
      return const {
        'title': 'Scan result',
        'dish': 'Dish',
        'confidence': 'Confidence',
        'nutrition': 'Nutrition',
        'similar_recipes': 'Similar recipes',
        'close': 'Close',
        'no_nutrition_data': 'No nutrition data',
        'failed_to_recognize': 'Failed to recognize dish',
        'kcal': 'kcal',
        'g': 'g',
        'mg': 'mg',
        'calories': 'Calories',
        'fat': 'Fat',
        'fats': 'Fat',
        'protein': 'Protein',
        'proteins': 'Protein',
        'carbohydrates': 'Carbs',
        'carbs': 'Carbs',
        'carb': 'Carbs',
        'fiber': 'Fiber',
        'sugar': 'Sugar',
        'sodium': 'Sodium',
        'saturated_fat': 'Sat. fat',
        'fiber_total': 'Fiber',
        'add_to_plan': 'Add to plan',
        'add_to_favorites': 'Add to favorites',
        'retry': 'Retry',
        'no_similar_recipes':
            'No similar recipes found. Try searching by dish name in Menu.',
        'portion': 'Portion',
        'nutrition_per_portion': 'Nutrition for this portion',
      };
    case 'es':
      return const {
        'title': 'Resultado del escaneo',
        'dish': 'Plato',
        'confidence': 'Confianza',
        'nutrition': 'Valor nutricional',
        'similar_recipes': 'Recetas similares',
        'close': 'Cerrar',
        'no_nutrition_data': 'Sin datos nutricionales',
        'failed_to_recognize': 'No se pudo reconocer el plato',
        'kcal': 'kcal',
        'g': 'g',
        'mg': 'mg',
        'calories': 'Calorías',
        'fat': 'Grasas',
        'fats': 'Grasas',
        'protein': 'Proteínas',
        'proteins': 'Proteínas',
        'carbohydrates': 'Carbohidratos',
        'carbs': 'Carbohidratos',
        'carb': 'Carbohidratos',
        'fiber': 'Fibra',
        'sugar': 'Azúcar',
        'sodium': 'Sodio',
        'saturated_fat': 'Grasas sat.',
        'fiber_total': 'Fibra',
        'add_to_plan': 'Añadir al plan',
        'add_to_favorites': 'Añadir a favoritos',
        'retry': 'Reintentar',
        'no_similar_recipes':
            'No se encontraron recetas similares. Prueba a buscar por nombre del plato en Menú.',
        'portion': 'Porción',
        'nutrition_per_portion': 'Nutrición para esta porción',
      };
    case 'de':
      return const {
        'title': 'Scan-Ergebnis',
        'dish': 'Gericht',
        'confidence': 'Konfidenz',
        'nutrition': 'Nährwert',
        'similar_recipes': 'Ähnliche Rezepte',
        'close': 'Schließen',
        'no_nutrition_data': 'Keine Nährwertdaten',
        'failed_to_recognize': 'Gericht konnte nicht erkannt werden',
        'kcal': 'kcal',
        'g': 'g',
        'mg': 'mg',
        'calories': 'Kalorien',
        'fat': 'Fett',
        'fats': 'Fett',
        'protein': 'Protein',
        'proteins': 'Protein',
        'carbohydrates': 'Kohlenhydrate',
        'carbs': 'Kohlenhydrate',
        'carb': 'Kohlenhydrate',
        'fiber': 'Ballaststoffe',
        'sugar': 'Zucker',
        'sodium': 'Natrium',
        'saturated_fat': 'Ges. Fett',
        'fiber_total': 'Ballaststoffe',
        'add_to_plan': 'Zum Plan hinzufügen',
        'add_to_favorites': 'Zu Favoriten',
        'retry': 'Wiederholen',
        'no_similar_recipes':
            'Keine ähnlichen Rezepte gefunden. Suche im Menü nach dem Gerichtsnamen.',
        'portion': 'Portion',
        'nutrition_per_portion': 'Nährwerte für diese Portion',
      };
    case 'fr':
      return const {
        'title': 'Résultat du scan',
        'dish': 'Plat',
        'confidence': 'Confiance',
        'nutrition': 'Valeur nutritionnelle',
        'similar_recipes': 'Recettes similaires',
        'close': 'Fermer',
        'no_nutrition_data': 'Aucune donnée nutritionnelle',
        'failed_to_recognize': 'Impossible de reconnaître le plat',
        'kcal': 'kcal',
        'g': 'g',
        'mg': 'mg',
        'calories': 'Calories',
        'fat': 'Lipides',
        'fats': 'Lipides',
        'protein': 'Protéines',
        'proteins': 'Protéines',
        'carbohydrates': 'Glucides',
        'carbs': 'Glucides',
        'carb': 'Glucides',
        'fiber': 'Fibres',
        'sugar': 'Sucres',
        'sodium': 'Sodium',
        'saturated_fat': 'Lipides sat.',
        'fiber_total': 'Fibres',
        'add_to_plan': 'Ajouter au plan',
        'add_to_favorites': 'Ajouter aux favoris',
        'retry': 'Réessayer',
        'no_similar_recipes':
            'Aucune recette similaire trouvée. Essayez une recherche par nom de plat dans Menu.',
        'portion': 'Portion',
        'nutrition_per_portion': 'Nutrition pour cette portion',
      };
    case 'ru':
    default:
      return const {
        'title': 'Результат сканирования',
        'dish': 'Блюдо',
        'confidence': 'Уверенность',
        'nutrition': 'Пищевая ценность',
        'similar_recipes': 'Похожие рецепты',
        'close': 'Закрыть',
        'no_nutrition_data': 'Нет данных о пищевой ценности',
        'failed_to_recognize': 'Не удалось распознать блюдо',
        'kcal': 'ккал',
        'g': 'г',
        'mg': 'мг',
        'calories': 'Калории',
        'fat': 'Жиры',
        'fats': 'Жиры',
        'protein': 'Белки',
        'proteins': 'Белки',
        'carbohydrates': 'Углеводы',
        'carbs': 'Углеводы',
        'carb': 'Углеводы',
        'fiber': 'Клетчатка',
        'sugar': 'Сахар',
        'sodium': 'Натрий',
        'saturated_fat': 'Насыщ. жиры',
        'fiber_total': 'Клетчатка',
        'add_to_plan': 'Добавить в план',
        'add_to_favorites': 'В избранное',
        'retry': 'Повторить',
        'no_similar_recipes':
            'Похожие рецепты не найдены. Попробуйте поиск по названию блюда в разделе «Меню».',
        'portion': 'Порция',
        'nutrition_per_portion': 'КБЖУ на эту порцию',
      };
  }
}

class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  AnalysisResult? _analysis;
  Object? _error;
  bool _loadingCore = true;
  bool _loadingRecipes = false;
  bool _paywallAnalyticsLogged = false;

  bool _needsEnhance(AnalysisResult a) {
    final label = _effectiveDishLabel(a);
    if (label.length > 2 && a.recipes.length < 2) return true;
    if (label.length > 2 && !_hasMacroNutrition(a)) return true;
    if (label.isEmpty && a.recipes.isEmpty && !_hasNutrition(a)) return true;
    return false;
  }

  Future<void> _runScan() async {
    final settings = ref.read(analysisSettingsProvider);
    setState(() {
      _loadingCore = true;
      _loadingRecipes = false;
      _error = null;
      _analysis = null;
    });

    try {
      final prepared = await prepareImageForAiScan(widget.bytes);
      await ScanResultCache.instance.loadFromDisk();
      final cached = ScanResultCache.instance.get(prepared);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _analysis = cached;
          _loadingCore = false;
          _loadingRecipes = false;
        });
        return;
      }

      final reserve = await ApiService.reserveAiScan();

      unawaited(
        ProductAnalytics.logEvent(
          eventType: 'ai_scan_reserve_ok',
          metadata: {'is_plus': reserve.isPlus},
        ),
      );

      var core = await _analyzeCore(
        prepared: prepared,
        ticket: reserve.ticket,
        settings: settings,
      );

      if (!mounted) return;
      setState(() {
        _analysis = core;
        _loadingCore = false;
        _loadingRecipes = true;
      });

      core = await _loadSimilarRecipes(core, settings);

      if (_needsEnhance(core)) {
        core = await _enhanceScanResult(core, settings.language, settings.mode);
      }

      if (!mounted) return;
      setState(() {
        _analysis = core;
        _loadingRecipes = false;
      });
      await ScanResultCache.instance.put(prepared, core);
    } catch (e) {
      if (e is HanLoginRequiredException) {
        unawaited(FeedLoadHelper.clearSessionIfExpired(e));
        return;
      }
      if (e is HanPlusRequiredException ||
          e is AiScansExhaustedException ||
          e is AiScanReserveRequiredException ||
          e is AiScanBackendMissingException) {
        if (!mounted) return;
        setState(() {
          _error = e;
          _loadingCore = false;
          _loadingRecipes = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingCore = false;
        _loadingRecipes = false;
      });
    }
  }

  bool _hasMacroNutrition(AnalysisResult a) {
    final n = a.nutrition;
    if (n == null || n.isEmpty) return false;
    num? pick(String k) {
      final v = n[k] ?? n[k[0].toUpperCase() + k.substring(1)];
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    final protein = pick('protein') ?? pick('proteins');
    final fat = pick('fat') ?? pick('fats');
    final carbs = pick('carbohydrates') ?? pick('carbs') ?? pick('carb');
    return (protein != null && protein > 0) ||
        (fat != null && fat > 0) ||
        (carbs != null && carbs > 0);
  }

  bool _hasNutrition(AnalysisResult a) =>
      _hasMacroNutrition(a) || (a.calories != null && a.calories! > 0);

  static bool _isWeakDishLabel(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.length < 3) return true;
    const weak = {
      'похожие рецепты',
      'блюдо',
      'еда',
      'food',
      'dish',
      'meal',
      'similar recipes',
    };
    return weak.contains(t);
  }

  String _effectiveDishLabel(AnalysisResult result) {
    final dish = (result.translatedLabel ?? result.label ?? '').trim();
    if (_isWeakDishLabel(dish)) return '';
    return dish;
  }

  AnalysisResult _filterScanRecipes(AnalysisResult result) {
    if (result.recipes.isEmpty) return result;
    final dish = _effectiveDishLabel(result);
    final filtered = ScanRecipeRanking.filterForScan(result.recipes, dish);
    return AnalysisResult(
      label: result.label,
      translatedLabel: result.translatedLabel,
      confidence: result.confidence,
      calories: result.calories,
      nutrition: result.nutrition,
      recipes: filtered,
      portionGrams: result.portionGrams,
    );
  }

  /// КБЖУ с GPT, название/похожие рецепты — с API (Spoonacular).
  AnalysisResult _mergeGptNutrition(AnalysisResult api, AnalysisResult gpt) {
    final apiMacros = _hasMacroNutrition(api);
    final gptMacros = _hasMacroNutrition(gpt);
    Map<String, dynamic>? nutrition;
    if (apiMacros && gptMacros) {
      nutrition = {...?gpt.nutrition, ...?api.nutrition};
    } else if (apiMacros) {
      nutrition = api.nutrition;
    } else {
      nutrition = gpt.nutrition ?? api.nutrition;
    }

    final gptLabel = (gpt.translatedLabel ?? gpt.label ?? '').trim();
    final apiLabel = (api.translatedLabel ?? api.label ?? '').trim();

    return AnalysisResult(
      label: gptLabel.isNotEmpty ? gpt.label ?? gptLabel : api.label,
      translatedLabel: gptLabel.isNotEmpty
          ? gptLabel
          : (apiLabel.isNotEmpty ? apiLabel : null),
      confidence: gpt.confidence ?? api.confidence,
      calories: gpt.calories ?? api.calories,
      nutrition: nutrition,
      recipes: api.recipes.isNotEmpty ? api.recipes : gpt.recipes,
      portionGrams: gpt.portionGrams ?? api.portionGrams,
    );
  }

  Future<AnalysisResult> _analyzeCore({
    required Uint8List prepared,
    required String ticket,
    required AnalysisSettingsState settings,
  }) async {
    try {
      var result = await ApiService.analyzePhoto(
        prepared,
        mode: settings.mode,
        language: settings.language,
        aiScanTicket: ticket,
        timeout: const Duration(seconds: 28),
      );

      final dishName = (result.translatedLabel ?? result.label ?? '').trim();
      final needsGpt = !_hasNutrition(result) || dishName.length < 3;
      if (needsGpt && GptAnalyzeService.isAvailable) {
        try {
          final gpt = await GptAnalyzeService.analyzePhotoCore(
            prepared,
            language: settings.language,
          );
          result = _mergeGptNutrition(result, gpt);
          unawaited(
            ProductAnalytics.logEvent(
              eventType: 'ai_scan_analyze_ok',
              metadata: {'source': 'api+gpt_nutrition'},
            ),
          );
        } catch (e) {
          debugPrint('GPT nutrition supplement failed: $e');
          unawaited(
            ProductAnalytics.logEvent(
              eventType: 'ai_scan_analyze_ok',
              metadata: {'source': 'api', 'gpt_supplement': 'failed'},
            ),
          );
        }
      } else {
        unawaited(
          ProductAnalytics.logEvent(
            eventType: 'ai_scan_analyze_ok',
            metadata: {'source': 'api'},
          ),
        );
      }
      return _filterScanRecipes(result);
    } catch (e) {
      if (e is HanPlusRequiredException ||
          e is HanLoginRequiredException ||
          e is AiScansExhaustedException ||
          e is AiScanReserveRequiredException ||
          e is AiScanBackendMissingException) {
        rethrow;
      }
      if (GptAnalyzeService.isAvailable) {
        final core = await GptAnalyzeService.analyzePhotoCore(
          prepared,
          language: settings.language,
        );
        unawaited(
          ProductAnalytics.logEvent(
            eventType: 'ai_scan_analyze_ok',
            metadata: {'source': 'gpt_fallback'},
          ),
        );
        return _filterScanRecipes(core);
      }
      rethrow;
    }
  }

  Future<AnalysisResult> _loadSimilarRecipes(
    AnalysisResult core,
    AnalysisSettingsState settings,
  ) async {
    final dish = _effectiveDishLabel(core);
    final filteredCore = _filterScanRecipes(core);
    if (filteredCore.recipes.isNotEmpty) {
      return filteredCore;
    }

    List<Recipe> recipes = [];
    if (dish.trim().length > 2) {
      try {
        recipes = await ApiService.searchRecipes(
          dish,
          mode: settings.mode,
          language: settings.language,
          timeout: const Duration(seconds: 12),
        );
        recipes = ScanRecipeRanking.filterForScan(recipes, dish);
        if (recipes.length > 6) {
          recipes = recipes.take(6).toList();
        }
      } catch (e) {
        debugPrint('Scan searchRecipes: $e');
      }
    }

    if (recipes.isEmpty && dish.trim().length > 2) {
      try {
        final rec = await ApiService.fetchRecommendations(
          limit: 6,
          ingredients: dish,
          mode: settings.mode,
          language: settings.language,
          timeout: const Duration(seconds: 12),
        );
        recipes = ScanRecipeRanking.filterForScan(rec.recipes, dish);
        if (recipes.length > 6) {
          recipes = recipes.take(6).toList();
        }
      } catch (e) {
        debugPrint('Scan recommendations: $e');
      }
    }

    return AnalysisResult(
      label: core.label,
      translatedLabel: core.translatedLabel,
      confidence: core.confidence,
      calories: core.calories,
      nutrition: core.nutrition,
      recipes: recipes,
      portionGrams: core.portionGrams,
    );
  }

  String _humanizeScanError(Object? error, Map<String, String> l10n) {
    if (error is HanPlusRequiredException) {
      return error.message;
    }
    if (error is HanLoginRequiredException) {
      return error.message;
    }
    if (error is AiScansExhaustedException) {
      return error.message ??
          (error.isPlus
              ? SubscriptionCopy.aiScanPlusExhaustedTitle
              : SubscriptionCopy.aiScanExhaustedTitle);
    }
    if (error is AiScanReserveRequiredException) {
      return error.message;
    }
    if (error is AiScanBackendMissingException) {
      return 'Сервис распознавания временно недоступен. Попробуйте позже.';
    }
    final raw = error?.toString() ?? '';
    if (raw.contains('403')) {
      return '${l10n['failed_to_recognize']}: доступ к сервису анализа ограничен (403). Попробуйте позже.';
    }
    if (raw.contains('502') || raw.contains('analysis failed')) {
      return '${l10n['failed_to_recognize']}: сервис анализа временно недоступен. Попробуйте другое фото или повторите позже.';
    }
    if (raw.contains('TimeoutException')) {
      return '${l10n['failed_to_recognize']}: превышено время ожидания сервера.';
    }
    final short = userVisibleError(
      error ?? Exception(raw),
      fallback: l10n['failed_to_recognize'] ?? 'Не удалось распознать блюдо',
    );
    return short;
  }

  /// Дополняет результат только при нехватке данных (без дублирующих запросов).
  Future<AnalysisResult> _enhanceScanResult(
    AnalysisResult analysis,
    String language,
    AnalysisMode mode,
  ) async {
    final normalizedLabel = _normalizeDishTitle(_effectiveDishLabel(analysis));
    var calories = analysis.calories;
    var nutrition = analysis.nutrition;
    var recipes =
        analysis.recipes.map((r) => _withNormalizedRecipeTitle(r)).toList();
    recipes = ScanRecipeRanking.filterForScan(recipes, normalizedLabel);

    final hasMacro = _hasMacroNutrition(analysis);
    final hasCalories = calories != null && calories > 0;

    if (recipes.length >= 2 && hasMacro && hasCalories) {
      return AnalysisResult(
        label: normalizedLabel.isEmpty ? analysis.label : normalizedLabel,
        translatedLabel: normalizedLabel.isEmpty
            ? analysis.translatedLabel
            : normalizedLabel,
        confidence: analysis.confidence,
        calories: calories,
        nutrition: nutrition,
        recipes: recipes,
        portionGrams: analysis.portionGrams,
      );
    }

    if (!_hasMacroNutrition(analysis) || calories == null) {
      final nutritionSource =
          ScanRecipeRanking.pickNutritionSource(recipes, normalizedLabel);
      if (nutritionSource != null) {
        calories ??= nutritionSource.calories;
        if ((nutrition == null || nutrition.isEmpty) &&
            nutritionSource.nutrition != null &&
            nutritionSource.nutrition!.isNotEmpty) {
          nutrition = nutritionSource.nutrition;
        }
      }
    }

    return AnalysisResult(
      label: normalizedLabel.isEmpty ? analysis.label : normalizedLabel,
      translatedLabel:
          normalizedLabel.isEmpty ? analysis.translatedLabel : normalizedLabel,
      confidence: analysis.confidence,
      calories: calories,
      nutrition: nutrition,
      recipes: recipes,
      portionGrams: analysis.portionGrams,
    );
  }

  void _loadAnalysis() => _runScan();

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Map<String, String> _l10n(BuildContext context) {
    final lang = ref.watch(analysisSettingsProvider).language;
    return _scanResultStrings(lang);
  }

  static RecipeModel _recipeToRecipeModel(Recipe r) {
    final stepsList = <String>[];
    if (r.translatedSteps != null) {
      for (final step in r.translatedSteps!) {
        stepsList.add(step['step']?.toString() ?? step.toString());
      }
    } else if (r.steps.isNotEmpty) {
      for (final step in r.steps) {
        stepsList.add(step['step']?.toString() ?? step.toString());
      }
    }
    return RecipeModel(
      id: r.id.toString(),
      title: r.translatedTitle ?? r.title,
      cookTime: 30,
      ingredients: r.translatedIngredients ?? r.ingredients,
      steps: stepsList,
      image: r.image ?? r.sourceImage,
      updatedAt: DateTime.now(),
      calories: r.calories?.toDouble(),
      proteinG: r.nutrientGrams('Protein'),
      carbsG: r.nutrientGrams('Carbohydrates'),
      fatG: r.nutrientGrams('Fat'),
    );
  }

  void _addFirstRecipeToPlan(AnalysisResult analysis) {
    if (analysis.recipes.isEmpty) return;
    final recipeModel = _recipeToRecipeModel(analysis.recipes.first);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => AddToMealPlanScreen(
          recipe: recipeModel,
          initialMealType: MealType.lunch,
        ),
      ),
    )
        .then((result) {
      if (mounted && result is DateTime) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${recipeModel.title} добавлен в план')),
        );
      }
    });
  }

  Future<void> _addFirstRecipeToFavorites(AnalysisResult analysis) async {
    if (analysis.recipes.isEmpty) return;
    try {
      await ApiService.addFavorite(analysis.recipes.first);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Добавлено в избранное')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  _ScanMacros _extractMacros(AnalysisResult analysis) {
    final dishLabel = analysis.translatedLabel ?? analysis.label ?? '';
    final nutrition = analysis.nutrition ??
        ScanRecipeRanking.extractNutrition(analysis.recipes, dishLabel);
    final calories = analysis.calories ??
        ScanRecipeRanking.extractCalories(analysis.recipes, dishLabel);

    double? parseNumber(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) {
        return double.tryParse(
          v.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '.'),
        );
      }
      return null;
    }

    double? nutrientByNames(Set<String> names) {
      if (nutrition == null) return null;

      final nutrients = nutrition['nutrients'];
      if (nutrients is List) {
        for (final raw in nutrients) {
          if (raw is! Map) continue;
          final name =
              '${raw['name'] ?? raw['title'] ?? ''}'.trim().toLowerCase();
          if (names.contains(name)) {
            final amount = parseNumber(raw['amount'] ?? raw['value']);
            if (amount != null) return amount;
          }
        }
      }

      for (final e in nutrition.entries) {
        final key = e.key.toLowerCase();
        if (names.contains(key)) {
          final amount = parseNumber(e.value);
          if (amount != null) return amount;
        }
      }

      return null;
    }

    final protein = nutrientByNames(const {
      'protein',
      'proteins',
      'protein_g',
      'белки',
      'белок',
    });
    final fat = nutrientByNames(const {
      'fat',
      'fats',
      'fat_g',
      'жиры',
      'жир',
    });
    final carbs = nutrientByNames(const {
      'carbohydrates',
      'carbs',
      'carb',
      'carbs_g',
      'carbohydrates_g',
      'углеводы',
      'углевод',
    });
    final estimatedCalories = calories ??
        (protein != null || fat != null || carbs != null
            ? (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
            : null);

    return _ScanMacros(
      calories: estimatedCalories?.round(),
      protein: protein,
      fat: fat,
      carbs: carbs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        title: Text(l10n['title']!),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (_loadingCore) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: scanResultBottomBarInset(context),
              ),
              child: const AiMealPlanLoadingView(
                message: 'Распознаём блюдо…\nОбычно 3–8 секунд',
              ),
            );
          }
          if (_error != null) {
            final bottom = floatingBottomPadding(context);
            final err = _error;
            if (err is AiScansExhaustedException) {
              if (!_paywallAnalyticsLogged) {
                _paywallAnalyticsLogged = true;
                ProductAnalytics.logEvent(
                  eventType: 'ai_scan_paywall_view',
                  metadata: {'is_plus': err.isPlus},
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottom),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: AiScanExhaustedPaywall(
                        isPlus: err.isPlus,
                        title: err.isPlus
                            ? (err.message ??
                                SubscriptionCopy.aiScanPlusExhaustedTitle)
                            : null,
                        subtitle: err.isPlus
                            ? SubscriptionCopy.aiScanPlusExhaustedSubtitle
                            : null,
                        onChoosePlan: () {
                          ProductAnalytics.logEvent(
                            eventType: 'ai_scan_paywall_cta',
                          );
                          context.push(
                            SubscriptionRoute.pathWithProduct('ai'),
                          );
                        },
                        onClose: () => context.pop(),
                      ),
                    ),
                  );
                },
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _humanizeScanError(err, l10n),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (err is HanPlusRequiredException) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          context.push(SubscriptionRoute.pathWithProduct('ai')),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('Оформить H.A.N. AI'),
                    ),
                  ],
                  if (err is AiScanBackendMissingException) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      err.toString(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                  if (err is! AiScansExhaustedException) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _loadAnalysis(),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n['retry']!),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => context.pop(),
                          child: Text(l10n['close']!),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }
          final analysis = _analysis!;
          final rawDish = analysis.translatedLabel ?? analysis.label ?? '';
          final dishTitle = _isWeakDishLabel(rawDish)
              ? l10n['dish']!
              : _normalizeDishTitle(rawDish);
          final macros = _extractMacros(analysis);
          final bottomInset = scanResultBottomBarInset(context);

          return RefreshIndicator(
            onRefresh: () async {
              final settings = ref.read(analysisSettingsProvider);
              setState(() => _loadingRecipes = true);
              try {
                var updated = await _loadSimilarRecipes(analysis, settings);
                if (_needsEnhance(updated)) {
                  updated = await _enhanceScanResult(
                    updated,
                    settings.language,
                    settings.mode,
                  );
                }
                if (!mounted) return;
                setState(() {
                  _analysis = updated;
                  _loadingRecipes = false;
                });
              } catch (e) {
                if (!mounted) return;
                setState(() => _loadingRecipes = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      userVisibleError(
                        e,
                        fallback: 'Не удалось обновить похожие рецепты',
                      ),
                    ),
                  ),
                );
              }
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ScanResultHero(
                      imageBytes: widget.bytes,
                      title: dishTitle,
                      confidencePercent: analysis.confidence != null
                          ? (analysis.confidence! * 100).round()
                          : null,
                      portionLine: analysis.portionGrams != null &&
                              analysis.portionGrams! > 0
                          ? '${l10n['portion']}: ~${_formatNum(analysis.portionGrams!)} ${l10n['g']}'
                          : null,
                      portionHint: analysis.portionGrams != null &&
                              analysis.portionGrams! > 0
                          ? l10n['nutrition_per_portion']
                          : null,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (macros.calories != null &&
                          macros.calories! > 0 &&
                          ((macros.protein ?? 0) > 0 ||
                              (macros.fat ?? 0) > 0 ||
                              (macros.carbs ?? 0) > 0))
                        AiMealPlanMacroRow(
                          calories: macros.calories,
                          protein: macros.protein,
                          fat: macros.fat,
                          carbs: macros.carbs,
                        )
                      else if (macros.calories != null && macros.calories! > 0)
                        ScanResultSection(
                          title: l10n['nutrition']!,
                          child: Text(
                            '${l10n['calories']!}: ${macros.calories} ${l10n['kcal']!}. '
                            '${l10n['no_nutrition_data']!}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        ScanResultSection(
                          title: l10n['nutrition']!,
                          child: Text(
                            l10n['no_nutrition_data']!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      ScanResultSection(
                        title: l10n['similar_recipes']!,
                        child: ScanResultRecipeCarousel(
                          recipes: analysis.recipes,
                          loading: _loadingRecipes,
                          emptyMessage: l10n['no_similar_recipes'],
                          kcalLabel: l10n['kcal']!,
                          onRecipeTap: (r) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => DetailPage(
                                  recipe: _withNormalizedRecipeTitle(r),
                                  isFavorite: false,
                                  onToggle: () {},
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _error == null
          ? ScanResultBottomBar(
              onAddToPlan: !_loadingCore &&
                      _analysis != null &&
                      _analysis!.recipes.isNotEmpty
                  ? () => _addFirstRecipeToPlan(_analysis!)
                  : null,
              onAddToFavorites: !_loadingCore &&
                      _analysis != null &&
                      _analysis!.recipes.isNotEmpty
                  ? () => _addFirstRecipeToFavorites(_analysis!)
                  : null,
              onClose: () => context.pop(),
              planLabel: l10n['add_to_plan']!,
              favoritesLabel: l10n['add_to_favorites']!,
              closeLabel: l10n['close']!,
            )
          : null,
    );
  }

  static String _formatNum(num n) {
    if (n == n.round()) return n.round().toString();
    return n.toStringAsFixed(1);
  }

  static String _normalizeDishTitle(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return cleaned;
    final withoutUnderscore = cleaned.replaceAll('_', ' ');
    return _capitalizeFirst(withoutUnderscore);
  }

  static String _capitalizeFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  static Recipe _withNormalizedRecipeTitle(Recipe recipe) {
    final normalized =
        _normalizeDishTitle(recipe.translatedTitle ?? recipe.title);
    if (normalized == recipe.title &&
        (recipe.translatedTitle == null ||
            recipe.translatedTitle == normalized)) {
      return recipe;
    }
    return Recipe(
      id: recipe.id,
      title: normalized,
      image: recipe.image,
      sourceImage: recipe.sourceImage,
      imageUrls: recipe.imageUrls,
      usedIngredientCount: recipe.usedIngredientCount,
      ingredients: recipe.ingredients,
      translatedIngredients: recipe.translatedIngredients,
      steps: recipe.steps,
      translatedSteps: recipe.translatedSteps,
      nutrition: recipe.nutrition,
      calories: recipe.calories,
      summary: recipe.summary,
      mode: recipe.mode,
      servings: recipe.servings,
      sourceLanguage: recipe.sourceLanguage,
      targetLanguage: recipe.targetLanguage,
      likesCount: recipe.likesCount,
      commentsCount: recipe.commentsCount,
      mealPlanCount: recipe.mealPlanCount,
      ratingCount: recipe.ratingCount,
      author: recipe.author,
      authorId: recipe.authorId,
      source: recipe.source,
      authorAvatar: recipe.authorAvatar,
      rating: recipe.rating,
      translatedTitle: normalized,
      videoUrl: recipe.videoUrl,
      videoThumbnail: recipe.videoThumbnail,
    );
  }
}

class _ScanMacros {
  const _ScanMacros({
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
  });

  final int? calories;
  final double? protein;
  final double? fat;
  final double? carbs;
}
