import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/meal_plan.dart';
import '../../../services/meal_plan_service.dart';
import '../../../services/shopping_service.dart';
import '../../../services/server_config.dart';
import '../../../app/app_router.dart';
import 'add_to_meal_plan_screen.dart';

class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('План питания'),
        actions: [
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
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        itemBuilder: (context, index) {
          final date = weekStart.add(Duration(days: index));
          final isSelected = _isSameDate(date, _selectedDate);
          final isToday = _isSameDate(date, now);
          
          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: Container(
              width: 60,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : isToday
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E', 'ru').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayPlan(DailyMealPlan plan) {
    if (plan.entries.isEmpty) {
      return Center(
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
          ],
        ),
      );
    }

    // Подсчитываем суммарные значения
    // Примечание: RecipeModel не содержит calories и nutrition,
    // поэтому подсчет макронутриентов недоступен для текущей модели
    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;
    
    // TODO: Добавить поля calories и nutrition в RecipeModel для подсчета макронутриентов

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Карточка с итоговой статистикой
        // Примечание: RecipeModel не содержит данные о калориях и макронутриентах
        // Карточка скрыта до тех пор, пока эти поля не будут добавлены в модель
        const SizedBox(height: 16),
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

  void _addMealForType(MealType mealType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddToMealPlanScreen(
          initialDate: _selectedDate,
          initialMealType: mealType,
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddToMealPlanScreen(),
      ),
    );
  }

  Future<void> _addDayToShoppingList() async {
    final plan = MealPlanService.instance.getPlanForDate(_selectedDate);
    if (plan.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На выбранный день нет блюд в плане')),
      );
      return;
    }
    int added = 0;
    for (final entry in plan.entries) {
      if (entry.recipe.ingredients.isNotEmpty) {
        await ShoppingService.instance.addItemsFromRecipe(
          entry.recipe.ingredients,
          group: entry.recipe.title,
        );
        added += entry.recipe.ingredients.length;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('В список покупок добавлено ингредиентов: $added'),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => context.push(ShoppingListRoute.path),
          ),
        ),
      );
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено из плана')),
        );
      }
    }
  }

  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  void _shareWeekPlan() {
    final entries = MealPlanService.instance.allEntries.value;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('План питания пуст')),
      );
      return;
    }
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final sb = StringBuffer();
    sb.writeln('План питания на неделю');
    sb.writeln(DateFormat('d MMM', 'ru').format(weekStart));
    sb.writeln('');
    for (var d = 0; d < 7; d++) {
      final date = weekStart.add(Duration(days: d));
      final dayEntries = entries.where((e) => _isSameDate(e.date, date)).toList()
        ..sort((a, b) => a.mealType.index.compareTo(b.mealType.index));
      if (dayEntries.isEmpty) continue;
      sb.writeln(DateFormat('EEEE, d MMM', 'ru').format(date));
      for (final e in dayEntries) {
        sb.writeln('  ${e.mealType.displayName}: ${e.recipe.title} (${e.servings} порц.)');
      }
      sb.writeln('');
    }
    Share.share(sb.toString(), subject: 'План питания');
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

