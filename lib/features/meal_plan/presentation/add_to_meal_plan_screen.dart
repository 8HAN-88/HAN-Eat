import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:intl/intl.dart';

import '../../../models/meal_plan.dart';
import '../../../models/post_model.dart';
import '../../../models/recipe_model.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/meal_plan_service.dart';
import '../../../services/server_config.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/saved_posts_service.dart';

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
  late DateTime _selectedDate;
  MealType? _selectedMealType;
  int _servings = 1;
  List<RecipeModel> _favoriteRecipes = [];
  bool _loading = false;
  bool _addingToPlan = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      final d = widget.initialDate!;
      _selectedDate = DateTime(d.year, d.month, d.day);
    } else {
      final n = DateTime.now();
      _selectedDate = DateTime(n.year, n.month, n.day);
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
      final merged = <String, RecipeModel>{};

      // 1) Основной источник: сохраненные рецепты пользователя (включая spoonacular/user/channel).
      final currentUser = await AuthService.getCurrentUser();
      if (currentUser != null) {
        final saved = await SavedPostsService.getSavedPosts(
          userId: currentUser.id,
          limit: 100,
          offset: 0,
          postType: 'recipe',
        );
        for (final post in saved.posts) {
          final mapped = _mapSavedPostToRecipeModel(post);
          if (mapped != null) {
            merged[mapped.id] = mapped;
          }
        }
      }

      // 2) Дополнительный источник: legacy /favorites (Redis), чтобы ничего не потерять.
      final favorites = await ApiService.getFavorites();
      for (final r in favorites) {
        final model = RecipeModel(
          id: r.id.toString(),
          title: r.translatedTitle?.isNotEmpty == true ? r.translatedTitle! : r.title,
          cookTime: 30,
          ingredients: r.translatedIngredients ?? r.ingredients,
          steps: (r.translatedSteps ?? r.steps)
              .map((step) => step['step']?.toString() ?? step.toString())
              .toList(),
          image: r.image ?? r.sourceImage,
          updatedAt: DateTime.now(),
        );
        merged[model.id] = model;
      }

      _favoriteRecipes = merged.values.toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e, fallback: 'Не удалось загрузить избранное'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  RecipeModel? _mapSavedPostToRecipeModel(PostModel post) {
    if (post.type != 'recipe') return null;
    final body = post.body ?? <String, dynamic>{};

    final titleCandidates = <String?>[
      post.title,
      body['translated_title']?.toString(),
      body['title']?.toString(),
      body['name']?.toString(),
    ];
    final title = titleCandidates
        .map((e) => e?.trim())
        .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
    if (title == null) return null;

    final rawIngredients = (body['translated_ingredients'] is List)
        ? body['translated_ingredients'] as List<dynamic>
        : ((body['ingredients'] is List) ? body['ingredients'] as List<dynamic> : const <dynamic>[]);
    final ingredients = rawIngredients
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    final rawSteps = (body['translated_steps'] is List)
        ? body['translated_steps'] as List<dynamic>
        : ((body['steps'] is List) ? body['steps'] as List<dynamic> : const <dynamic>[]);
    final steps = rawSteps.map((step) {
      if (step is Map<String, dynamic>) {
        return (step['step'] ?? step['text'] ?? step['instruction'] ?? '').toString().trim();
      }
      return step.toString().trim();
    }).where((e) => e.isNotEmpty).toList();

    String? image;
    final img = body['image']?.toString();
    final src = body['source_image']?.toString();
    if (img != null && img.trim().isNotEmpty) {
      image = img.trim();
    } else if (src != null && src.trim().isNotEmpty) {
      image = src.trim();
    }

    return RecipeModel(
      id: post.id.toString(),
      title: title,
      cookTime: 30,
      ingredients: ingredients,
      steps: steps,
      image: image,
      updatedAt: post.createdAt,
      calories: RecipeModel.parseOptionalDouble(body['calories']),
      proteinG: RecipeModel.parseOptionalDouble(
        body['protein_g'] ?? body['protein'],
      ),
      carbsG: RecipeModel.parseOptionalDouble(
        body['carbs_g'] ?? body['carbohydrates'],
      ),
      fatG: RecipeModel.parseOptionalDouble(body['fat_g'] ?? body['fat']),
    );
  }

  Future<void> _selectDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(today.year - 3, today.month, today.day),
      lastDate: DateTime(today.year + 2, today.month, today.day),
      locale: const Locale('ru', 'RU'),
    );
    if (picked != null) {
      setState(
        () => _selectedDate = DateTime(picked.year, picked.month, picked.day),
      );
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
        Navigator.of(context).pop(
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingToPlan = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userVisibleError(e)),
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
    final bottom = floatingBottomPadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
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
    final bottom = floatingBottomPadding(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
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
      ),
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

