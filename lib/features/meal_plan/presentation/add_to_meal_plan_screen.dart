import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/meal_plan.dart';
import '../../../models/recipe_model.dart';
import '../../../services/meal_plan_service.dart';
import '../../../services/favorites_service.dart';
import '../../../services/api_service.dart';
import '../../../services/server_config.dart';

class AddToMealPlanScreen extends StatefulWidget {
  final DateTime? initialDate;
  final MealType? initialMealType;
  final RecipeModel? recipe;

  const AddToMealPlanScreen({
    super.key,
    this.initialDate,
    this.initialMealType,
    this.recipe,
  });

  @override
  State<AddToMealPlanScreen> createState() => _AddToMealPlanScreenState();
}

class _AddToMealPlanScreenState extends State<AddToMealPlanScreen> {
  DateTime _selectedDate = DateTime.now();
  MealType? _selectedMealType;
  int _servings = 1;
  List<RecipeModel> _favoriteRecipes = [];
  bool _loading = false;
  bool _addingToPlan = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    }
    if (widget.initialMealType != null) {
      _selectedMealType = widget.initialMealType;
    }
    // Чтобы кнопка «Добавить в план» срабатывала сразу, выбираем обед по умолчанию
    if (widget.recipe != null && _selectedMealType == null) {
      _selectedMealType = MealType.lunch;
    }
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    try {
      // Загружаем избранные рецепты
      final favorites = FavoritesService.instance.favorites.value;
      // Здесь нужно загрузить полные данные рецептов по ID
      // Для упрощения используем пустой список
      _favoriteRecipes = [];
    } catch (e) {
      // Обработка ошибок
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _selectMealType(MealType type) {
    setState(() => _selectedMealType = type);
  }

  Future<void> _addToPlan(RecipeModel recipe) async {
    if (_selectedMealType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите тип приема пищи')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _addingToPlan = true);

    try {
      await MealPlanService.instance.addRecipeToPlan(
        recipe: recipe,
        mealType: _selectedMealType!,
        date: _selectedDate,
        servings: _servings,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${recipe.title} добавлен в план'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingToPlan = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted && _addingToPlan) setState(() => _addingToPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить в план питания'),
      ),
      body: widget.recipe != null
          ? _buildAddRecipeForm(widget.recipe!)
          : _buildRecipeSelector(),
    );
  }

  Widget _buildAddRecipeForm(RecipeModel recipe) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Рецепт
          Card(
            child: ListTile(
              leading: recipe.image != null && recipe.image!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        ServerConfig.resolveRecipeImageUrl(recipe.image!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, size: 48),
                      ),
                    )
                  : const Icon(Icons.restaurant),
              title: Text(recipe.title),
            ),
          ),
          const SizedBox(height: 16),

          // Дата
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Дата'),
              subtitle: Text(DateFormat('EEEE, d MMMM y', 'ru').format(_selectedDate)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectDate,
            ),
          ),
          const SizedBox(height: 16),

          // Тип приема пищи
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.restaurant_menu),
                  title: Text('Тип приема пищи'),
                ),
                ...MealType.values.map((type) => RadioListTile<MealType>(
                      title: Text(type.displayName),
                      value: type,
                      groupValue: _selectedMealType,
                      onChanged: (value) => _selectMealType(value!),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Порции
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.restaurant),
                  title: Text('Количество порций'),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _servings > 1
                          ? () => setState(() => _servings--)
                          : null,
                    ),
                    Text(
                      '$_servings',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _servings++),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Кнопка добавления
          ElevatedButton.icon(
            onPressed: _addingToPlan ? null : () => _addToPlan(recipe),
            icon: _addingToPlan
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(_addingToPlan ? 'Добавляем...' : 'Добавить в план'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeSelector() {
    return Column(
      children: [
        // Форма выбора даты и типа
        Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Дата'),
                subtitle: Text(DateFormat('EEEE, d MMMM y', 'ru').format(_selectedDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectDate,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('Тип приема пищи'),
                subtitle: Text(
                  _selectedMealType?.displayName ?? 'Не выбрано',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showMealTypeSelector(),
              ),
            ],
          ),
        ),

        // Список избранных рецептов
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _favoriteRecipes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет избранных рецептов',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Добавьте рецепты в избранное, чтобы добавить их в план',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _favoriteRecipes.length,
                      itemBuilder: (context, index) {
                        final recipe = _favoriteRecipes[index];
                        return ListTile(
                          leading: recipe.image != null && recipe.image!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    ServerConfig.resolveRecipeImageUrl(recipe.image!),
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, size: 40),
                                  ),
                                )
                              : const Icon(Icons.restaurant),
                          title: Text(recipe.title),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _addToPlan(recipe),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _showMealTypeSelector() async {
    final selected = await showDialog<MealType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите тип приема пищи'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: MealType.values.map((type) {
            return RadioListTile<MealType>(
              title: Text(type.displayName),
              value: type,
              groupValue: _selectedMealType,
              onChanged: (value) => Navigator.of(context).pop(value),
            );
          }).toList(),
        ),
      ),
    );

    if (selected != null) {
      setState(() => _selectedMealType = selected);
    }
  }
}

