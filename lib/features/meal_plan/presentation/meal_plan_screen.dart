import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/share/system_share.dart';
import 'dart:async';

import '../../../models/meal_plan.dart';
import '../../../services/meal_plan_service.dart';
import '../../../services/shopping_service.dart';
import '../../../services/server_config.dart';
import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import 'add_to_meal_plan_screen.dart';

class _DayNutritionTotals {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final bool hasData;

  const _DayNutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.hasData,
  });
}

class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late DateTime _selectedDate;
  /// Понедельник отображаемой недели (локальный календарь).
  late DateTime _visibleWeekStart;

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  DateTime _mondayOf(DateTime d) {
    final date = _dateOnly(d);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  void _showNotice(
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + floatingBottomPadding(context)),
        backgroundColor: cs.surfaceContainerHigh,
        content: Text(
          message,
          style: TextStyle(color: cs.onSurface),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        action: action,
      ),
    );
    // На части iOS-сборок SnackBar с action не всегда закрывается по duration.
    // Дублируем авто-скрытие таймером для предсказуемого UX.
    Timer(duration, () {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = _dateOnly(now);
    _visibleWeekStart = _mondayOf(_selectedDate);
  }

  void _shiftWeek(int deltaWeeks) {
    setState(() {
      _visibleWeekStart = _mondayOf(
        _visibleWeekStart.add(Duration(days: 7 * deltaWeeks)),
      );
      final dow = _selectedDate.weekday;
      _selectedDate = _dateOnly(
        _visibleWeekStart.add(Duration(days: dow - DateTime.monday)),
      );
    });
  }

  Future<void> _applyReturnedDate(DateTime? d) async {
    if (d != null && mounted) {
      setState(() {
        _selectedDate = _dateOnly(d);
        _visibleWeekStart = _mondayOf(_selectedDate);
      });
    }
  }

  Widget _weekDayChip({
    required ThemeData theme,
    required DateTime now,
    required DateTime day,
  }) {
    final isSelected = _isSameDate(day, _selectedDate);
    final isToday = _isSameDate(day, now);
    return GestureDetector(
      onTap: () => setState(() => _selectedDate = day),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : isToday
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected
              ? Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E', 'ru').format(day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('План питания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Аналитика AI-плана',
            onPressed: () => context.push(MealPlanAnalyticsRoute.path),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'AI-план питания',
            onPressed: () => context.push(AiMealPlanRoute.path),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareWeekPlan(),
            tooltip: 'Поделиться планом на неделю',
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => _addDayToShoppingList(),
            tooltip: 'Сформировать список покупок на выбранный день',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context),
            tooltip: 'Добавить рецепт',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWeekHeader(),
          Expanded(
            child: ValueListenableBuilder<List<MealPlanEntry>>(
              valueListenable: MealPlanService.instance.allEntries,
              builder: (context, allEntries, _) {
                final dailyPlan = MealPlanService.instance.getPlanForDate(_selectedDate);
                return _buildDayPlan(dailyPlan);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekHeader() {
    final now = _dateOnly(DateTime.now());
    final weekStart = _visibleWeekStart;
    final theme = Theme.of(context);
    final rangeEnd = weekStart.add(const Duration(days: 6));

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Предыдущая неделя',
                  onPressed: () => _shiftWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${DateFormat('d MMM', 'ru').format(weekStart)} — ${DateFormat('d MMM yyyy', 'ru').format(rangeEnd)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Следующая неделя',
                  onPressed: () => _shiftWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (var index = 0; index < 7; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _weekDayChip(
                          theme: theme,
                          now: now,
                          day: _dateOnly(weekStart.add(Duration(days: index))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayPlan(DailyMealPlan plan) {
    if (plan.entries.isEmpty) {
      final bottom = floatingBottomPadding(context);
      return Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Нет запланированных блюд',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите + чтобы добавить рецепт',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Добавить рецепт'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push(AiMealPlanRoute.path),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Создать AI-план'),
            ),
          ],
        ),
        ),
      );
    }

    final bottom = floatingBottomPadding(context);
    final totals = _aggregateDayNutrition(plan.entries);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      children: [
        if (totals.hasData) ...[
          _nutritionDayCard(context, totals),
          const SizedBox(height: 16),
        ],
        _buildMealSection(
          'Завтрак',
          MealType.breakfast,
          plan.getEntriesForMeal(MealType.breakfast),
        ),
        _buildMealSection(
          'Обед',
          MealType.lunch,
          plan.getEntriesForMeal(MealType.lunch),
        ),
        _buildMealSection(
          'Ужин',
          MealType.dinner,
          plan.getEntriesForMeal(MealType.dinner),
        ),
        _buildMealSection(
          'Перекус',
          MealType.snack,
          plan.getEntriesForMeal(MealType.snack),
        ),
      ],
    );
  }

  _DayNutritionTotals _aggregateDayNutrition(List<MealPlanEntry> entries) {
    var calories = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    var hasData = false;
    for (final e in entries) {
      final r = e.recipe;
      final s = e.servings.clamp(1, 999);
      if (r.calories != null) {
        calories += r.calories! * s;
        hasData = true;
      }
      if (r.proteinG != null) {
        protein += r.proteinG! * s;
        hasData = true;
      }
      if (r.carbsG != null) {
        carbs += r.carbsG! * s;
        hasData = true;
      }
      if (r.fatG != null) {
        fat += r.fatG! * s;
        hasData = true;
      }
    }
    return _DayNutritionTotals(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      hasData: hasData,
    );
  }

  Widget _nutritionDayCard(BuildContext context, _DayNutritionTotals totals) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'За день (по плану)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Калории: ${totals.calories.round()} ккал',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Б ${totals.protein.toStringAsFixed(0)} г · '
              'Ж ${totals.fat.toStringAsFixed(0)} г · '
              'У ${totals.carbs.toStringAsFixed(0)} г',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSection(
    String title,
    MealType mealType,
    List<MealPlanEntry> entries,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: Icon(_getMealIcon(mealType)),
        title: Text(title),
        subtitle: Text('${entries.length} блюд'),
        children: entries.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Нет блюд'),
                ),
              ]
            : entries.map((entry) => _buildMealEntry(entry)).toList()
          ..add(
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Добавить блюдо'),
              onTap: () => _addMealForType(mealType),
            ),
          ),
      ),
    );
  }

  Widget _buildMealEntry(MealPlanEntry entry) {
    return ListTile(
      leading: entry.recipe.image != null && entry.recipe.image!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                ServerConfig.resolveRecipeImageUrl(entry.recipe.image!),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.restaurant),
              ),
            )
          : const Icon(Icons.restaurant),
      title: Text(entry.recipe.title),
      subtitle: Text('${entry.servings} порций'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _removeEntry(entry),
      ),
      onTap: () {
        // Можно открыть детали рецепта
      },
    );
  }

  IconData _getMealIcon(MealType mealType) {
    switch (mealType) {
      case MealType.breakfast:
        return Icons.breakfast_dining;
      case MealType.lunch:
        return Icons.lunch_dining;
      case MealType.dinner:
        return Icons.dinner_dining;
      case MealType.snack:
        return Icons.cookie;
    }
  }

  Future<void> _addMealForType(MealType mealType) async {
    final d = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => AddToMealPlanScreen(
          initialDate: _selectedDate,
          initialMealType: mealType,
        ),
      ),
    );
    await _applyReturnedDate(d);
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final d = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => const AddToMealPlanScreen(),
      ),
    );
    await _applyReturnedDate(d);
  }

  Future<void> _addDayToShoppingList() async {
    final plan = MealPlanService.instance.getPlanForDate(_selectedDate);
    if (plan.entries.isEmpty) {
      _showNotice('На выбранный день нет блюд в плане');
      return;
    }

    final selectedEntries = await _selectEntriesForShopping(plan.entries);
    if (!mounted || selectedEntries == null || selectedEntries.isEmpty) return;

    final selectedIngredients = await _selectIngredientsForShopping(selectedEntries);
    if (!mounted || selectedIngredients == null || selectedIngredients.isEmpty) return;

    int added = 0;
    final byRecipe = <String, List<String>>{};
    for (final item in selectedIngredients) {
      byRecipe.putIfAbsent(item.recipeTitle, () => []).add(item.ingredient);
    }
    for (final row in byRecipe.entries) {
      await ShoppingService.instance.addItemsFromRecipe(
        row.value,
        group: row.key,
      );
      added += row.value.length;
    }
    if (mounted) {
      _showNotice(
        'Добавлено ингредиентов: $added',
        action: SnackBarAction(
          label: 'Открыть',
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            context.push(ShoppingListRoute.path);
          },
        ),
      );
    }
  }

  Future<List<MealPlanEntry>?> _selectEntriesForShopping(
    List<MealPlanEntry> entries,
  ) async {
    final selected = <String>{for (final e in entries) e.id};
    return showDialog<List<MealPlanEntry>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Добавить в список покупок'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Выбрать все'),
                          onPressed: () => setLocalState(() {
                            selected
                              ..clear()
                              ..addAll(entries.map((e) => e.id));
                          }),
                        ),
                        ActionChip(
                          label: const Text('Снять все'),
                          onPressed: () => setLocalState(() => selected.clear()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(entry.id),
                            title: Text(entry.recipe.title),
                            subtitle: Text(entry.mealType.displayName),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) {
                              setLocalState(() {
                                if (v == true) {
                                  selected.add(entry.id);
                                } else {
                                  selected.remove(entry.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          final result =
                              entries.where((e) => selected.contains(e.id)).toList();
                          Navigator.of(context).pop(result);
                        },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_IngredientPick>?> _selectIngredientsForShopping(
    List<MealPlanEntry> entries,
  ) async {
    final all = <_IngredientPick>[];
    for (final entry in entries) {
      for (final raw in entry.recipe.ingredients) {
        final ing = raw.trim();
        if (ing.isEmpty) continue;
        all.add(
          _IngredientPick(
            id: '${entry.id}|${ing.toLowerCase()}',
            recipeTitle: entry.recipe.title,
            ingredient: ing,
          ),
        );
      }
    }
    if (all.isEmpty) return null;

    final selected = <String>{for (final i in all) i.id};
    return showDialog<List<_IngredientPick>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Выберите продукты'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Выбрать все'),
                          onPressed: () => setLocalState(() {
                            selected
                              ..clear()
                              ..addAll(all.map((e) => e.id));
                          }),
                        ),
                        ActionChip(
                          label: const Text('Снять все'),
                          onPressed: () => setLocalState(() => selected.clear()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: all.length,
                        itemBuilder: (context, index) {
                          final item = all[index];
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(item.id),
                            title: Text(item.ingredient),
                            subtitle: Text(item.recipeTitle),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) {
                              setLocalState(() {
                                if (v == true) {
                                  selected.add(item.id);
                                } else {
                                  selected.remove(item.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          final result = all.where((e) => selected.contains(e.id)).toList();
                          Navigator.of(context).pop(result);
                        },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removeEntry(MealPlanEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить из плана?'),
        content: Text('Удалить "${entry.recipe.title}" из плана?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MealPlanService.instance.removeFromPlan(entry.id);
      _showNotice('Удалено из плана');
    }
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    final a = _dateOnly(date1);
    final b = _dateOnly(date2);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _shareWeekPlan() async {
    final entries = MealPlanService.instance.allEntries.value;
    if (entries.isEmpty) {
      _showNotice('План питания пуст');
      return;
    }
    final weekStart = _visibleWeekStart;
    final sb = StringBuffer();
    sb.writeln('План питания на неделю');
    sb.writeln(DateFormat('d MMM', 'ru').format(weekStart));
    sb.writeln('');
    for (var d = 0; d < 7; d++) {
      final date = _dateOnly(weekStart.add(Duration(days: d)));
      final dayEntries = entries.where((e) => _isSameDate(e.date, date)).toList()
        ..sort((a, b) => a.mealType.index.compareTo(b.mealType.index));
      if (dayEntries.isEmpty) continue;
      sb.writeln(DateFormat('EEEE, d MMM', 'ru').format(date));
      for (final e in dayEntries) {
        sb.writeln('  ${e.mealType.displayName}: ${e.recipe.title} (${e.servings} порц.)');
      }
      sb.writeln('');
    }
    await SystemShare.shareText(
      context,
      text: sb.toString(),
      subject: 'План питания',
    );
  }

  double? _getNutritionValue(Map<String, dynamic> nutrition, List<String> keys) {
    for (final key in keys) {
      final value = nutrition[key];
      if (value != null) {
        if (value is num) return value.toDouble();
        if (value is String) {
          final match = RegExp(r'(\d+\.?\d*)').firstMatch(value);
          if (match != null) return double.tryParse(match.group(1)!);
        }
      }
    }
    return null;
  }

  Widget _buildStatItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _IngredientPick {
  final String id;
  final String recipeTitle;
  final String ingredient;

  const _IngredientPick({
    required this.id,
    required this.recipeTitle,
    required this.ingredient,
  });
}

