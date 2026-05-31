import 'package:flutter/material.dart';

import '../../../../core/theme/color_schemes.dart';
import '../../../../models/ai_meal_plan.dart';
import '../../../subscription/presentation/widgets/subscription_visuals.dart';

class AiMetaChipData {
  const AiMetaChipData({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class AiRegenActionData {
  const AiRegenActionData({
    required this.label,
    required this.icon,
    this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

class MealTypeStyle {
  const MealTypeStyle({
    required this.label,
    required this.icon,
    required this.accent,
    required this.tint,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Color tint;

  static MealTypeStyle forType(String mealType) {
    switch (mealType) {
      case 'breakfast':
        return MealTypeStyle(
          label: 'Завтрак',
          icon: Icons.wb_sunny_rounded,
          accent: AppColors.secondary,
          tint: const Color(0xFFFFF4E6),
        );
      case 'dinner':
        return MealTypeStyle(
          label: 'Ужин',
          icon: Icons.nights_stay_rounded,
          accent: const Color(0xFF5C6BC0),
          tint: const Color(0xFFEEF0FA),
        );
      case 'snack':
        return MealTypeStyle(
          label: 'Перекус',
          icon: Icons.local_cafe_rounded,
          accent: AppColors.success,
          tint: const Color(0xFFE8F5E9),
        );
      default:
        return MealTypeStyle(
          label: 'Обед',
          icon: Icons.restaurant_rounded,
          accent: AppColors.primary,
          tint: const Color(0xFFFFEDE6),
        );
    }
  }
}

/// Шапка экрана с градиентом и краткой статистикой плана.
class AiMealPlanHero extends StatelessWidget {
  const AiMealPlanHero({
    super.key,
    required this.durationDays,
    required this.aiRecommendation,
    this.dayCalories,
  });

  final int durationDays;
  final String aiRecommendation;
  final int? dayCalories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
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
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI-план питания',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$durationDays ${_daysLabel(durationDays)} · персонально для вас',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (dayCalories != null && dayCalories! > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '~$dayCalories ккал сегодня',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (aiRecommendation.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              aiRecommendation,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.95),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _daysLabel(int d) {
    if (d == 1) return 'день';
    if (d < 5) return 'дня';
    return 'дней';
  }
}

/// Горизонтальные чипы мета-информации.
class AiMealPlanMetaRow extends StatelessWidget {
  const AiMealPlanMetaRow({
    super.key,
    required this.chips,
  });

  final List<AiMetaChipData> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = chips[i];
          final theme = Theme.of(context);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  c.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Селектор дней — капсулы с анимацией.
class AiMealPlanDaySelector extends StatelessWidget {
  const AiMealPlanDaySelector({
    super.key,
    required this.count,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int count;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Material(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surface,
              elevation: selected ? 2 : 0,
              shadowColor: AppColors.primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    'День ${i + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Макросы дня в виде карточек.
class AiMealPlanMacroRow extends StatelessWidget {
  const AiMealPlanMacroRow({
    super.key,
    required this.calories,
    this.protein,
    this.fat,
    this.carbs,
  });

  final int? calories;
  final double? protein;
  final double? fat;
  final double? carbs;

  @override
  Widget build(BuildContext context) {
    if (calories == null || calories! <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _MacroTile(
            label: 'Ккал',
            value: '$calories',
            icon: Icons.local_fire_department_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroTile(
            label: 'Белки',
            value: '${protein?.round() ?? 0}',
            icon: Icons.egg_alt_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroTile(
            label: 'Жиры',
            value: '${fat?.round() ?? 0}',
            icon: Icons.water_drop_rounded,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroTile(
            label: 'Углев.',
            value: '${carbs?.round() ?? 0}',
            icon: Icons.grain_rounded,
            color: const Color(0xFF5C6BC0),
          ),
        ),
      ],
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Горизонтальная полоса действий регенерации.
class AiMealPlanRegenBar extends StatelessWidget {
  const AiMealPlanRegenBar({
    super.key,
    required this.actions,
  });

  final List<AiRegenActionData> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = actions[i];
          final enabled = a.onTap != null;
          return ActionChip(
            avatar: Icon(
              a.icon,
              size: 18,
              color: enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            label: Text(a.label),
            onPressed: a.onTap,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }
}

/// Карточка приёма пищи.
class AiMealPlanMealCard extends StatelessWidget {
  const AiMealPlanMealCard({
    super.key,
    required this.meal,
    required this.loading,
    required this.canRegenerate,
    required this.onReplace,
    required this.onRecipeTap,
  });

  final AiMealBlock meal;
  final bool loading;
  final bool canRegenerate;
  final VoidCallback? onReplace;
  final void Function(AiMealPlanRecipe recipe) onRecipeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = MealTypeStyle.forType(meal.mealType);
    final cal = meal.nutrition['calories'];
    final isDark = theme.brightness == Brightness.dark;
    final headerTint = isDark
        ? style.accent.withValues(alpha: 0.14)
        : style.tint;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              color: headerTint,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: style.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(style.icon, color: style.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          style.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: style.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (cal != null)
                          Text(
                            '~${cal.round()} ккал',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Заменить блюдо',
                      onPressed: canRegenerate ? onReplace : null,
                      icon: Icon(
                        Icons.autorenew_rounded,
                        color: canRegenerate
                            ? style.accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (meal.guidance.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              meal.guidance,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (meal.ingredients.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Ингредиенты',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: meal.ingredients.map((ing) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            ing,
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (meal.recommendedRecipes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Подходящие рецепты',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 132,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: meal.recommendedRecipes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          return _RecipeCard(
                            recipe: meal.recommendedRecipes[i],
                            onTap: () => onRecipeTap(meal.recommendedRecipes[i]),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onTap});

  final AiMealPlanRecipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                child: recipe.imageUrl != null
                    ? Image.network(
                        recipe.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(theme),
                      )
                    : _placeholder(theme),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (recipe.calories != null || recipe.cookTimeMin != null)
                      Text(
                        [
                          if (recipe.calories != null) '${recipe.calories} ккал',
                          if (recipe.cookTimeMin != null) '${recipe.cookTimeMin} мин',
                        ].join(' · '),
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

/// Нижняя панель действий.
class AiMealPlanBottomBar extends StatelessWidget {
  const AiMealPlanBottomBar({
    super.key,
    required this.onCalendar,
    required this.onShopping,
  });

  final VoidCallback onCalendar;
  final VoidCallback onShopping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
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
          Expanded(
            child: FilledButton.icon(
              onPressed: onCalendar,
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              label: const Text('В календарь'),
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
            onPressed: onShopping,
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: 'Список покупок',
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

/// Пункт меню действий плана (bottom sheet).
class AiMealPlanMenuTile extends StatelessWidget {
  const AiMealPlanMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Загрузка с брендовым оформлением.
class AiMealPlanLoadingView extends StatelessWidget {
  const AiMealPlanLoadingView({super.key, this.message = 'Составляем ваш план…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: subscriptionBrandGradientDecoration(
                radius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран до первого AI-плана: анкета только по кнопке.
class AiMealPlanStartView extends StatelessWidget {
  const AiMealPlanStartView({
    super.key,
    required this.onCreatePlan,
    this.onOpenSaved,
    this.surveyComplete = false,
  });

  final VoidCallback onCreatePlan;
  final VoidCallback? onOpenSaved;
  final bool surveyComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: subscriptionBrandGradientDecoration(
                radius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Персональный план от AI',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    surveyComplete
                        ? 'Выберите срок и мы соберём меню под ваши ответы.'
                        : 'Сначала короткая анкета — вопросы по одному, с учётом вашей цели.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreatePlan,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                surveyComplete ? 'Создать план' : 'Составить AI-план',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            if (onOpenSaved != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onOpenSaved,
                child: const Text('Сохранённые планы'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ошибка / пустое состояние.
class AiMealPlanErrorView extends StatelessWidget {
  const AiMealPlanErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
