import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../models/recipe.dart';
import '../../../../utils/image_url_helper.dart';
import '../../../../widgets/recipe_network_image.dart';
import '../../../meal_plan/presentation/widgets/ai_meal_plan_widgets.dart';
import '../../../subscription/presentation/widgets/subscription_visuals.dart';

/// Шапка результата сканирования — фото + градиентный блок как в AI-плане.
class ScanResultHero extends StatelessWidget {
  const ScanResultHero({
    super.key,
    required this.imageBytes,
    required this.title,
    this.confidencePercent,
    this.portionLine,
    this.portionHint,
  });

  final Uint8List imageBytes;
  final String title;
  final int? confidencePercent;
  final String? portionLine;
  final String? portionHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Image.memory(
                imageBytes,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 80,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          decoration: subscriptionBrandGradientDecoration(
            radius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.document_scanner_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI-сканирование',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (confidencePercent != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Уверенность: $confidencePercent%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
              if (portionLine != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        portionLine!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (portionHint != null && portionHint!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          portionHint!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Горизонтальная карусель похожих рецептов (как в AI-плане).
class ScanResultRecipeCarousel extends StatelessWidget {
  const ScanResultRecipeCarousel({
    super.key,
    required this.recipes,
    required this.onRecipeTap,
    this.loading = false,
    this.emptyMessage,
    this.kcalLabel = 'ккал',
  });

  final List<Recipe> recipes;
  final void Function(Recipe recipe) onRecipeTap;
  final bool loading;
  final String? emptyMessage;
  final String kcalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return const SizedBox(
        height: 132,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (recipes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          emptyMessage ?? 'Похожие рецепты не найдены',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recipes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final r = recipes[i];
          return _ScanRecipeTile(
            recipe: r,
            kcalLabel: kcalLabel,
            onTap: () => onRecipeTap(r),
          );
        },
      ),
    );
  }
}

class _ScanRecipeTile extends StatelessWidget {
  const _ScanRecipeTile({
    required this.recipe,
    required this.onTap,
    required this.kcalLabel,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final String kcalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = recipe.image ?? recipe.sourceImage ?? '';

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: imageUrl.isNotEmpty
                    ? RecipeNetworkImage(
                        rawUrl: getRecipeCardImageUrl(imageUrl),
                        profile: RecipeImageProfile.card,
                        fit: BoxFit.cover,
                        errorWidget: _placeholder(theme),
                      )
                    : _placeholder(theme),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.translatedTitle ?? recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (recipe.calories != null)
                      Text(
                        '${recipe.calories} $kcalLabel',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.restaurant_menu_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Отступ контента над нижней панелью результата сканирования.
double scanResultBottomBarInset(BuildContext context) {
  return MediaQuery.paddingOf(context).bottom + 64;
}

/// Нижняя панель действий результата сканирования.
class ScanResultBottomBar extends StatelessWidget {
  const ScanResultBottomBar({
    super.key,
    this.onAddToPlan,
    this.onAddToFavorites,
    required this.onClose,
    this.planLabel = 'В план',
    this.favoritesLabel = 'В избранное',
    this.closeLabel = 'Готово',
  });

  final VoidCallback? onAddToPlan;
  final VoidCallback? onAddToFavorites;
  final VoidCallback onClose;
  final String planLabel;
  final String favoritesLabel;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final hasRecipes = onAddToPlan != null;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + safeBottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          if (hasRecipes) ...[
            Expanded(
              child: FilledButton.icon(
                onPressed: onAddToPlan,
                icon: const Icon(Icons.calendar_month_rounded, size: 20),
                label: Text(planLabel),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onAddToFavorites,
              icon: const Icon(Icons.favorite_border_rounded),
              tooltip: favoritesLabel,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            Expanded(
              child: FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(closeLabel),
              ),
            ),
          if (hasRecipes)
            IconButton.filledTonal(
              onPressed: onClose,
              icon: const Icon(Icons.check_rounded),
              tooltip: closeLabel,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Секция с заголовком в стиле AI-плана.
class ScanResultSection extends StatelessWidget {
  const ScanResultSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// Мета-чипы для скана (обёртка над AiMealPlanMetaRow).
class ScanResultMetaChips extends StatelessWidget {
  const ScanResultMetaChips({super.key, required this.chips});

  final List<AiMetaChipData> chips;

  @override
  Widget build(BuildContext context) => AiMealPlanMetaRow(chips: chips);
}
