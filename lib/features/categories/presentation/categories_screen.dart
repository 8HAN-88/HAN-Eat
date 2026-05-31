import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../subscription/presentation/widgets/nutrition_upsell.dart';
import '../../../core/subscription/recipe_nutrition_access.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../models/recipe_category.dart';
import '../../../services/category_service.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  Future<void> _openDietSettings() async {
    final canView = ref.read(canViewRecipeNutritionProvider);
    if (!canView) {
      await showNutritionUpsellSheet(context);
      return;
    }
    if (!mounted) return;
    context.push(DietRoute.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Категории рецептов'),
        actions: [
          TextButton(
            onPressed: () {
              CategoryService.instance.resetAllFilters();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Все фильтры сброшены')),
              );
            },
            child: const Text('Сбросить все'),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<CategoryFilter>>(
        valueListenable: CategoryService.instance.filters,
        builder: (context, filters, _) {
          if (filters.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final bottom = floatingBottomPadding(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
            children: [
              _buildSectionCard(
                context: context,
                icon: Icons.warning_amber_outlined,
                title: 'Аллергии',
                subtitle: 'Аллергены и непереносимости',
                hint: 'Используются для фильтрации рецептов и рекомендаций — рецепты с выбранными аллергенами не показываются.',
                onTap: () => context.push(AllergiesRoute.path),
              ),
              _buildSectionCard(
                context: context,
                icon: Icons.restaurant_menu,
                title: 'Диета',
                subtitle: 'Калории, БЖУ на блюдо, тип диеты',
                hint: 'Лимиты по калориям и БЖУ помогают подбирать рецепты под ваши цели (похудение, набор массы, ЗОЖ).',
                onTap: _openDietSettings,
              ),
              _buildCategoryGroup(context, 'Практические', CategoryType.practical, filters),
              _buildCategoryGroup(context, 'Тип приема пищи', CategoryType.mealType, filters),
              _buildCategoryGroup(context, 'Кухни мира', CategoryType.cuisine, filters),
            ],
          );
        },
      ),
    );
  }

  static const _cardMargin = EdgeInsets.only(bottom: 16);
  static const _sectionPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

  /// Общая карточка-секция: либо переход по тапу (onTap), либо раскрывающийся блок (children).
  Widget _buildSectionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    String? hint,
    VoidCallback? onTap,
    List<Widget>? children,
  }) {
    final theme = Theme.of(context);
    final leading = Icon(icon, color: theme.colorScheme.primary, size: 28);

    if (onTap != null) {
      return Card(
        margin: _cardMargin,
        child: ListTile(
          leading: leading,
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: subtitle != null || hint != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (subtitle != null) Text(subtitle, style: theme.textTheme.bodySmall),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                )
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
          contentPadding: _sectionPadding,
        ),
      );
    }

    return Card(
      margin: _cardMargin,
      child: ExpansionTile(
        leading: leading,
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: subtitle != null ? Text(subtitle, style: theme.textTheme.bodySmall) : null,
        tilePadding: _sectionPadding,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: children ?? [],
      ),
    );
  }

  Widget _buildCategoryGroup(
    BuildContext context,
    String title,
    CategoryType type,
    List<CategoryFilter> allFilters,
  ) {
    final categories = CategoryService.instance.getCategoriesByType(type);
    final activeCount = categories
        .where((cat) => CategoryService.instance.isCategoryActive(cat))
        .length;
    final subtitle = activeCount > 0 ? '$activeCount выбрано' : 'Ничего не выбрано';

    return _buildSectionCard(
      context: context,
      icon: _getTypeIcon(type),
      title: title,
      subtitle: subtitle,
      children: categories.map((category) {
        final filter = allFilters.firstWhere(
          (f) => f.category == category,
          orElse: () => CategoryFilter(category: category),
        );
        return _buildCategoryTile(category, filter.isActive);
      }).toList(),
    );
  }

  Widget _buildCategoryTile(RecipeCategory category, bool isActive) {
    return SwitchListTile(
      secondary: Icon(
        _getCategoryIcon(category.iconName),
        color: _getCategoryColor(category.color),
      ),
      title: Text(category.displayName),
      subtitle: Text(
        category.description,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: isActive,
      onChanged: (value) async {
        if (value &&
            RecipeNutritionAccess.isNutritionCategory(category) &&
            !ref.read(canViewRecipeNutritionProvider)) {
          await showNutritionUpsellSheet(context);
          return;
        }
        CategoryService.instance.toggleCategory(category, value);
        setState(() {});
      },
    );
  }

  IconData _getCategoryIcon(String iconName) {
    switch (iconName) {
      case 'favorite':
        return Icons.favorite;
      case 'attach_money':
        return Icons.attach_money;
      case 'water_drop':
        return Icons.water_drop;
      case 'schedule':
        return Icons.schedule;
      case 'eco':
        return Icons.eco;
      case 'spa':
        return Icons.spa;
      case 'grain':
        return Icons.grain;
      case 'no_food':
        return Icons.no_food;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'cake':
        return Icons.cake;
      case 'breakfast_dining':
        return Icons.breakfast_dining;
      case 'lunch_dining':
        return Icons.lunch_dining;
      case 'dinner_dining':
        return Icons.dinner_dining;
      case 'cookie':
        return Icons.cookie;
      case 'ramen_dining':
        return Icons.ramen_dining;
      case 'local_dining':
        return Icons.local_dining;
      case 'set_meal':
        return Icons.set_meal;
      case 'wine_bar':
        return Icons.wine_bar;
      case 'takeout_dining':
        return Icons.takeout_dining;
      case 'rice_bowl':
        return Icons.rice_bowl;
      case 'spicy':
        return Icons.local_fire_department; // Острая еда
// Тайская кухня
      case 'circle':
        return Icons.circle;
      case 'tapas':
        return Icons.restaurant; // Тапас - ресторан
      case 'sports_bar':
        return Icons.sports_bar;
      case 'soup_kitchen':
        return Icons.soup_kitchen;
      case 'fastfood':
        return Icons.fastfood;
      case 'kebab':
        return Icons.restaurant_menu; // Кебаб - меню ресторана
      case 'outdoor_grill':
        return Icons.outdoor_grill;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String colorName) {
    switch (colorName) {
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(CategoryType type) {
    switch (type) {
      case CategoryType.practical:
        return Icons.tune;
      case CategoryType.dietary:
        return Icons.eco;
      case CategoryType.mealType:
        return Icons.restaurant_menu;
      case CategoryType.cuisine:
        return Icons.public;
    }
  }
}

