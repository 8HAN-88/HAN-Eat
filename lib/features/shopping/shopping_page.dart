import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/share/system_share.dart';
import '../../models/post_model.dart';
import '../../models/meal_plan.dart';
import '../../models/recipe_model.dart';
import '../../models/shopping_item.dart';
import '../../services/shopping_service.dart';
import '../../services/meal_plan_service.dart';
import '../../services/auth_service.dart';
import '../../services/saved_posts_service.dart';
import '../../services/api_service.dart';
import '../../services/server_config.dart';
import '../../core/layout/long_label_tab_bar.dart';
import '../../utils/api_error_parser.dart';
import '../../widgets/app_empty_state.dart';

class _RecipeSourceItem {
  final RecipeModel recipe;
  final DateTime? mealDate;
  final bool isMealPlan;
  final String sourceLabel;
  const _RecipeSourceItem({
    required this.recipe,
    required this.sourceLabel,
    this.mealDate,
    this.isMealPlan = false,
  });
}

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key});

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  final _groupController = TextEditingController();
  final _itemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // При открытии экрана подгружаем список из хранилища (сохраняется между сессиями и выходом).
    ShoppingService.instance.reloadFromStorage();
  }

  @override
  void dispose() {
    _groupController.dispose();
    _itemController.dispose();
    super.dispose();
  }

  Future<void> _addFromRecipe() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    List<_RecipeSourceItem> recipes;
    try {
      recipes = await _loadRecipeSources();
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось загрузить рецепты'),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (recipes.isEmpty) {
      final loggedIn = AuthService.instance.currentUser != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loggedIn
                ? 'Добавьте рецепты в избранное или план питания'
                : 'Войдите, чтобы подтянуть избранное, или добавьте блюда в план',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RecipeSourceListScreen(
          recipes: recipes,
          onAddIngredients: (ingredients, group) => _addRecipeIngredients(ingredients, group: group),
        ),
      ),
    );
  }

  Future<void> _addRecipeIngredients(
    List<String> ingredients, {
    String? group,
  }) async {
    if (ingredients.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В рецепте нет ингредиентов для добавления')),
        );
      }
      return;
    }
    await ShoppingService.instance.addItemsFromRecipe(
      ingredients,
      group: (group != null && group.trim().isNotEmpty) ? group.trim() : null,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено: ${ingredients.length}')),
      );
    }
  }

  Future<List<_RecipeSourceItem>> _loadRecipeSources() async {
    final merged = <String, _RecipeSourceItem>{};

    for (final entry in MealPlanService.instance.allEntries.value) {
      final recipe = entry.recipe;
      final key = 'plan:${entry.id}:${recipe.id}';
      merged[key] = _RecipeSourceItem(
        recipe: recipe,
        sourceLabel: 'План питания (${entry.mealType.displayName})',
        mealDate: entry.date,
        isMealPlan: true,
      );
    }

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
          final key = 'fav:saved:${mapped.id}';
          merged.putIfAbsent(key, () => _RecipeSourceItem(
            recipe: mapped,
            sourceLabel: 'Избранное',
            isMealPlan: false,
          ));
        }
      }
    }

    try {
      final favorites = await ApiService.getFavorites();
      for (final r in favorites) {
        final model = RecipeModel(
          id: r.id.toString(),
          title: r.translatedTitle?.isNotEmpty == true
              ? r.translatedTitle!
              : r.title,
          cookTime: 30,
          ingredients: r.translatedIngredients ?? r.ingredients,
          steps: (r.translatedSteps ?? r.steps)
              .map((step) => step['step']?.toString() ?? step.toString())
              .toList(),
          image: r.image ?? r.sourceImage,
          updatedAt: DateTime.now(),
        );
        merged.putIfAbsent(
          'fav:legacy:${model.id}',
          () => _RecipeSourceItem(
            recipe: model,
            sourceLabel: 'Избранное',
            isMealPlan: false,
          ),
        );
      }
    } catch (_) {
      // Избранное с API недоступно — остаются план и сохранённые посты.
    }

    final list = merged.values.toList();
    list.sort((a, b) => b.recipe.updatedAt.compareTo(a.recipe.updatedAt));
    return list;
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

  Future<void> _openAddManualDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final nameController = TextEditingController();
        final groupController = TextEditingController();
        return AlertDialog(
          title: const Text('Добавить продукт'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: groupController,
                decoration: const InputDecoration(
                  labelText: 'Подгруппа (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ['Овощи', 'Фрукты', 'Молочное', 'Мясо', 'Рыба', 'Бакалея'].map((g) {
                  return ActionChip(
                    label: Text(g),
                    onPressed: () {
                      groupController.text = g;
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final groupName = groupController.text.trim();
                Navigator.pop(context);
                await ShoppingService.instance.addItem(
                  name,
                  group: groupName.isEmpty ? null : groupName,
                );
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  Widget _bottomActionsBar(double navBottom) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + navBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: _addFromRecipe,
              icon: const Icon(Icons.restaurant_menu_outlined),
              label: const Text('Из рецепта'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openAddManualDialog,
              icon: const Icon(Icons.add, size: 22),
              label: const Text('Добавить вручную'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _departmentOrderList = [
    'Овощи', 'Фрукты', 'Молочное', 'Мясо', 'Рыба', 'Бакалея', 'Заморозка', 'Напитки',
  ];

  int _departmentOrder(String? key) {
    if (key == null || key.isEmpty) return 999;
    final i = _departmentOrderList.indexOf(key);
    return i >= 0 ? i : 500;
  }

  Future<void> _shareList() async {
    final items = ShoppingService.instance.items.value;
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Список пуст')),
        );
      }
      return;
    }
    final json = {'items': items.map((e) => e.toJson()).toList()};
    final data = base64Url.encode(utf8.encode(jsonEncode(json)));
    final link = 'haneat://shopping/import?data=$data';
    final text = 'Список покупок — откройте в приложении H.A.N. Eat и добавьте к себе:\n$link';
    await SystemShare.shareText(
      context,
      text: text,
      subject: 'Список покупок',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Ссылка скопирована в буфер обмена'
                : 'Ссылка на список отправлена',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final navBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Список продуктов'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Поделиться списком',
            onPressed: _shareList,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Очистить список',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Очистить список?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Нет')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Да')),
                  ],
                ),
              );
              if (ok == true) await ShoppingService.instance.clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ShoppingItem>>(
        valueListenable: ShoppingService.instance.items,
        builder: (context, list, _) {
          final bar = _bottomActionsBar(navBottom);
          if (list.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AppEmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Список пуст',
                    subtitle: 'Добавьте продукты вручную или из рецепта',
                  ),
                ),
                bar,
              ],
            );
          }
          final grouped = ShoppingService.instance.getGrouped();
          final keys = grouped.keys.toList()
            ..sort((a, b) => _departmentOrder(a).compareTo(_departmentOrder(b)));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final itemsInGroup = grouped[key]!;
                    final groupLabel = key == null || key.isEmpty ? 'Без группы' : key;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Text(
                            groupLabel,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        ...itemsInGroup.map((item) => ListTile(
                              contentPadding: const EdgeInsetsDirectional.only(
                                start: 0,
                                end: 4,
                              ),
                              leading: Checkbox(
                                value: item.purchased,
                                onChanged: (v) => ShoppingService.instance
                                    .togglePurchased(item, v ?? false),
                              ),
                              title: Text(
                                item.name,
                                style: item.purchased
                                    ? TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      )
                                    : null,
                              ),
                              subtitle: item.quantity != null &&
                                      item.quantity!.isNotEmpty
                                  ? Text(
                                      item.quantity!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    )
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => ShoppingService.instance.removeItem(item),
                              ),
                            )),
                      ],
                    );
                  },
                ),
              ),
              bar,
            ],
          );
        },
      ),
    );
  }
}

class _RecipeSourceListScreen extends StatelessWidget {
  final List<_RecipeSourceItem> recipes;
  final Future<void> Function(List<String> ingredients, String? group) onAddIngredients;

  const _RecipeSourceListScreen({
    required this.recipes,
    required this.onAddIngredients,
  });

  @override
  Widget build(BuildContext context) {
    final favorites = recipes.where((e) => !e.isMealPlan).toList();
    final mealPlan = recipes.where((e) => e.isMealPlan).toList();
    final mealByDay = <String, List<_RecipeSourceItem>>{};
    for (final item in mealPlan) {
      final key = _dayKey(item.mealDate);
      mealByDay.putIfAbsent(key, () => []).add(item);
    }
    final dayKeys = mealByDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Выберите рецепт'),
          bottom: longLabelTabBar(
            tabs: const [
              Tab(text: 'Избранные'),
              Tab(text: 'План питания'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRecipeList(context, favorites, mealPlanTab: false),
            _buildMealPlanDayList(context, dayKeys, mealByDay),
          ],
        ),
      ),
    );
  }

  Widget _buildMealPlanDayList(
    BuildContext context,
    List<String> dayKeys,
    Map<String, List<_RecipeSourceItem>> mealByDay,
  ) {
    if (dayKeys.isEmpty) {
      return _buildRecipeList(context, const [], mealPlanTab: true);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: dayKeys.map((day) {
        final items = mealByDay[day] ?? const <_RecipeSourceItem>[];
        return Card(
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(_dayLabel(day)),
            children: items.map((item) => _buildRecipeTile(context, item)).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecipeList(
    BuildContext context,
    List<_RecipeSourceItem> data, {
    required bool mealPlanTab,
  }) {
    if (data.isEmpty) {
      return AppEmptyState(
        icon: mealPlanTab
            ? Icons.calendar_today_outlined
            : Icons.favorite_border_rounded,
        title: mealPlanTab ? 'План питания пуст' : 'Нет избранных рецептов',
        subtitle: mealPlanTab
            ? 'Добавьте блюда в план на неделю'
            : 'Сохраняйте рецепты в избранное в меню',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildRecipeTile(context, data[i]),
    );
  }

  Widget _buildRecipeTile(BuildContext context, _RecipeSourceItem item) {
    return ListTile(
      leading: item.recipe.image != null && item.recipe.image!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                ServerConfig.resolveRecipeImageUrl(item.recipe.image!),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.restaurant),
              ),
            )
          : const Icon(Icons.restaurant),
      title: Text(item.recipe.title),
      subtitle: Text(item.sourceLabel),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _RecipeIngredientsCardScreen(
              item: item,
              onAddIngredients: onAddIngredients,
            ),
          ),
        );
      },
    );
  }

  String _dayKey(DateTime? dt) {
    if (dt == null) return 'unknown';
    final d = DateTime(dt.year, dt.month, dt.day);
    return d.toIso8601String().substring(0, 10);
  }

  String _dayLabel(String key) {
    if (key == 'unknown') return 'Без даты';
    final dt = DateTime.tryParse(key);
    if (dt == null) return key;
    return DateFormat('EEEE, d MMMM', 'ru').format(dt);
  }
}

class _RecipeIngredientsCardScreen extends StatefulWidget {
  final _RecipeSourceItem item;
  final Future<void> Function(List<String> ingredients, String? group) onAddIngredients;

  const _RecipeIngredientsCardScreen({
    required this.item,
    required this.onAddIngredients,
  });

  @override
  State<_RecipeIngredientsCardScreen> createState() => _RecipeIngredientsCardScreenState();
}

class _RecipeIngredientsCardScreenState extends State<_RecipeIngredientsCardScreen> {
  final _groupController = TextEditingController();
  final _scrollController = ScrollController();
  late final List<String> _ingredients;
  late final Set<int> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ingredients = widget.item.recipe.ingredients.where((e) => e.trim().isNotEmpty).toList();
    _selected = {for (int i = 0; i < _ingredients.length; i++) i};
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.item.recipe;
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка рецепта')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (recipe.image != null && recipe.image!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            ServerConfig.resolveRecipeImageUrl(recipe.image!),
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    Text(
                      recipe.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 16),
                      child: Text(
                        widget.item.sourceLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    TextField(
                      controller: _groupController,
                      decoration: const InputDecoration(
                        labelText: 'Подгруппа (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'Ингредиенты',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Выбрать все'),
                            onPressed: () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(List.generate(_ingredients.length, (i) => i));
                            }),
                          ),
                          ActionChip(
                            label: const Text('Убрать все'),
                            onPressed: () => setState(() => _selected.clear()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _ingredients.isEmpty
                          ? Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                'Ингредиенты не найдены',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            )
                          : ListView.builder(
                              key: const PageStorageKey('shopping-recipe-ingredients-scroll'),
                              controller: _scrollController,
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const ClampingScrollPhysics(),
                              itemCount: _ingredients.length,
                              itemBuilder: (context, i) {
                                final ing = _ingredients[i];
                                return CheckboxListTile(
                                  key: ValueKey('ingredient-$i-$ing'),
                                  contentPadding: EdgeInsets.zero,
                                  value: _selected.contains(i),
                                  title: Text(ing),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(i);
                                      } else {
                                        _selected.remove(i);
                                      }
                                    });
                                  },
                                  secondary: IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    tooltip: 'Убрать из добавления',
                                    onPressed: () => setState(() => _selected.remove(i)),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final selectedIngredients = _selected.map((i) => _ingredients[i]).toList();
                          if (selectedIngredients.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Выберите хотя бы один ингредиент')),
                            );
                            return;
                          }
                          setState(() => _saving = true);
                          await widget.onAddIngredients(
                            selectedIngredients,
                            _groupController.text.trim().isEmpty ? null : _groupController.text.trim(),
                          );
                          if (mounted) {
                            setState(() => _saving = false);
                            Navigator.of(context).pop();
                          }
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add),
                  label: const Text('Добавить продукты в список'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
