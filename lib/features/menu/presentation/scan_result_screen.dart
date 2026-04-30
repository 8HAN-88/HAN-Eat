import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/analysis_result.dart';
import '../../../models/recipe.dart';
import '../../../models/recipe_model.dart';
import '../../../models/meal_plan.dart';
import '../../../screens/detail_page.dart';
import '../../../services/api_service.dart';
import '../../../services/gpt_analyze_service.dart';
import '../../../services/server_config.dart';
import '../../settings/application/analysis_mode_controller.dart';
import '../../meal_plan/presentation/add_to_meal_plan_screen.dart';

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
  late Future<AnalysisResult> _future;

  void _loadAnalysis() {
    final settings = ref.read(analysisSettingsProvider);
    setState(() {
      if (GptAnalyzeService.isAvailable) {
        _future = GptAnalyzeService.analyzePhoto(
          widget.bytes,
          language: settings.language,
        );
      } else {
        _future = ApiService.analyzePhoto(
          widget.bytes,
          mode: settings.mode,
          language: settings.language,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
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
    );
  }

  void _addFirstRecipeToPlan(AnalysisResult analysis) {
    if (analysis.recipes.isEmpty) return;
    final recipeModel = _recipeToRecipeModel(analysis.recipes.first);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddToMealPlanScreen(
          recipe: recipeModel,
          initialMealType: MealType.lunch,
        ),
      ),
    ).then((added) {
      if (added == true && mounted) {
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
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n['title']!),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<AnalysisResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${l10n['failed_to_recognize']}: ${snapshot.error}',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
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
              ),
            );
          }
          final analysis = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              _loadAnalysis();
              await _future;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Image.memory(
                    widget.bytes,
                    height: 280,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        analysis.translatedLabel ?? analysis.label ?? l10n['dish']!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (analysis.confidence != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${l10n['confidence']}: ${(analysis.confidence! * 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n['nutrition']!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ..._buildNutritionList(analysis, l10n),
                      const SizedBox(height: 24),
                      if (analysis.recipes.isNotEmpty) ...[
                        Text(
                          l10n['similar_recipes']!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ...analysis.recipes.map((r) => _buildRecipeTile(context, r, l10n)),
                        const SizedBox(height: 24),
                      ],
                      Row(
                        children: [
                          if (analysis.recipes.isNotEmpty) ...[
                            FilledButton.icon(
                              onPressed: () => _addFirstRecipeToPlan(analysis),
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(l10n['add_to_plan']!),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _addFirstRecipeToFavorites(analysis),
                              icon: const Icon(Icons.favorite_border, size: 18),
                              label: Text(l10n['add_to_favorites']!),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Spacer(),
                          FilledButton(
                            onPressed: () => context.pop(),
                            child: Text(l10n['close']!),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildNutritionList(AnalysisResult analysis, Map<String, String> l10n) {
    final theme = Theme.of(context);
    final list = <Widget>[];
    if (analysis.calories != null) {
      final c = analysis.calories!;
      list.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.local_fire_department, color: theme.colorScheme.primary),
          title: Text(l10n['calories']!),
          trailing: Text('${_formatNum(c)} ${l10n['kcal']}', style: theme.textTheme.titleSmall),
        ),
      );
    }
    final nutrition = analysis.nutrition;
    if (nutrition != null && nutrition.isNotEmpty) {
      for (final entry in nutrition.entries) {
        final v = entry.value;
        num? n;
        if (v is num) n = v;
        if (v is String) n = num.tryParse(v);
        if (n == null) continue;
        final label = _nutritionLabel(entry.key, l10n);
        final unit = _nutritionUnit(entry.key, l10n);
        list.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_nutritionIcon(entry.key), color: theme.colorScheme.outline),
            title: Text(label),
            trailing: Text('${_formatNum(n)} $unit', style: theme.textTheme.titleSmall),
          ),
        );
      }
    }
    if (list.isEmpty) {
      list.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n['no_nutrition_data']!,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return list;
  }

  static String _nutritionLabel(String key, Map<String, String> l10n) {
    final k = key.toLowerCase();
    return l10n[k] ?? l10n['fat'] ?? key;
  }

  static String _nutritionUnit(String key, Map<String, String> l10n) {
    final k = key.toLowerCase();
    if (k == 'sodium') return l10n['mg']!;
    return l10n['g']!;
  }

  static IconData _nutritionIcon(String key) {
    final k = key.toLowerCase();
    if (k.contains('fat')) return Icons.opacity;
    if (k.contains('protein') || k.contains('proteins')) return Icons.fitness_center;
    if (k.contains('carb') || k.contains('fiber') || k.contains('sugar')) return Icons.grain;
    if (k.contains('sodium')) return Icons.water_drop_outlined;
    return Icons.restaurant;
  }

  static String _formatNum(num n) {
    if (n == n.round()) return n.round().toString();
    return n.toStringAsFixed(1);
  }

  Widget _buildRecipeTile(BuildContext context, Recipe recipe, Map<String, String> l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            context.pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailPage(
                  recipe: recipe,
                  isFavorite: false,
                  onToggle: () {},
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (recipe.image != null && recipe.image!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      ServerConfig.resolveRecipeImageUrl(recipe.image!),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.restaurant, size: 36),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.restaurant, size: 36),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        recipe.translatedTitle ?? recipe.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (recipe.calories != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${recipe.calories} ${l10n['kcal']}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
