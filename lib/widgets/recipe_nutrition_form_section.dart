import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../features/settings/application/subscription_status_provider.dart';
import '../features/subscription/presentation/widgets/creator_recipe_upsell.dart';
import '../features/subscription/subscription_copy.dart';
import '../services/recipe_nutrition_ai_service.dart';
import '../utils/api_error_parser.dart';

/// Блок КБЖУ: ручной ввод + AI (Creator).
class RecipeNutritionFormSection extends ConsumerStatefulWidget {
  const RecipeNutritionFormSection({
    super.key,
    required this.caloriesController,
    required this.proteinController,
    required this.carbsController,
    required this.fatController,
    required this.fiberController,
    required this.getTitle,
    required this.getIngredients,
    required this.getStepTexts,
    this.getServings,
    this.getDescription,
  });

  final TextEditingController caloriesController;
  final TextEditingController proteinController;
  final TextEditingController carbsController;
  final TextEditingController fatController;
  final TextEditingController fiberController;
  final String Function() getTitle;
  final List<String> Function() getIngredients;
  final List<String> Function() getStepTexts;
  final int? Function()? getServings;
  final String? Function()? getDescription;

  @override
  ConsumerState<RecipeNutritionFormSection> createState() =>
      _RecipeNutritionFormSectionState();
}

class _RecipeNutritionFormSectionState
    extends ConsumerState<RecipeNutritionFormSection> {
  bool _analyzing = false;

  void _applyResult(RecipeNutritionResult r) {
    if (r.calories != null) {
      widget.caloriesController.text = r.calories.toString();
    }
    if (r.proteinG != null) {
      widget.proteinController.text = _fmt(r.proteinG!);
    }
    if (r.carbsG != null) {
      widget.carbsController.text = _fmt(r.carbsG!);
    }
    if (r.fatG != null) {
      widget.fatController.text = _fmt(r.fatG!);
    }
    if (r.fiberG != null) {
      widget.fiberController.text = _fmt(r.fiberG!);
    }
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  Future<void> _runAi() async {
    final hasCreator =
        ref.read(subscriptionStatusProvider).asData?.value?.hasCreator ??
            false;
    if (!hasCreator) {
      await showCreatorRecipeUpsellSheet(context);
      return;
    }

    final title = widget.getTitle().trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала укажите название рецепта')),
      );
      return;
    }
    final ingredients = widget.getIngredients();
    if (ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы один ингредиент')),
      );
      return;
    }

    setState(() => _analyzing = true);
    try {
      final result = await RecipeNutritionAiService.analyzeRecipe(
        title: title,
        description: widget.getDescription?.call(),
        ingredients: ingredients,
        steps: widget.getStepTexts(),
        servings: widget.getServings?.call() ?? 1,
      );
      if (!mounted) return;
      _applyResult(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Питание рассчитано AI')),
      );
    } on ApiClientException catch (e) {
      if (!mounted) return;
      if (e.code == 'HAN_CREATOR_REQUIRED') {
        await showCreatorRecipeUpsellSheet(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось рассчитать питание'))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Ошибка AI-запроса'))),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCreator =
        ref.watch(subscriptionStatusProvider).asData?.value?.hasCreator ??
            false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                SubscriptionCopy.recipeNutritionSectionTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _analyzing ? null : _runAi,
              icon: _analyzing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : Icon(
                      hasCreator ? Icons.auto_awesome : Icons.lock_outline,
                      size: 18,
                    ),
              label: Text(
                hasCreator
                    ? SubscriptionCopy.recipeNutritionAiCta
                    : SubscriptionCopy.recipeNutritionAiLockedCta,
              ),
            ),
          ],
        ),
        if (!hasCreator) ...[
          const SizedBox(height: 6),
          Text(
            SubscriptionCopy.recipeNutritionAiLockedHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(
            onPressed: () =>
                context.push(SubscriptionRoute.pathWithProduct('creator')),
            child: Text(SubscriptionCopy.recipeVisibilityPrivateCta),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.caloriesController,
          decoration: const InputDecoration(
            labelText: 'Калории (ккал)',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.proteinController,
                decoration: const InputDecoration(
                  labelText: 'Белки (г)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: widget.carbsController,
                decoration: const InputDecoration(
                  labelText: 'Углеводы (г)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.fatController,
                decoration: const InputDecoration(
                  labelText: 'Жиры (г)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: widget.fiberController,
                decoration: const InputDecoration(
                  labelText: 'Клетчатка (г)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
