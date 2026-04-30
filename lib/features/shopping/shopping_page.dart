import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/shopping_item.dart';
import '../../services/shopping_service.dart';

class _AddFromRecipeResult {
  final List<String> ingredients;
  final String? group;
  _AddFromRecipeResult({required this.ingredients, this.group});
}

class ShoppingPage extends StatefulWidget {
  const ShoppingPage({Key? key}) : super(key: key);

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
    final result = await showDialog<_AddFromRecipeResult>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        final groupController = TextEditingController();
        return AlertDialog(
          title: const Text('Добавить из рецепта'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Вставьте ингредиенты (каждый с новой строки). Можно указать подгруппу.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: groupController,
                  decoration: const InputDecoration(
                    labelText: 'Подгруппа (например: Овощи)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'мука 200 г\nяйца 2 шт.\n...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text;
                final list = text
                    .split(RegExp(r'[\n,;]+'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (list.isEmpty) {
                  Navigator.pop(context, null);
                  return;
                }
                final groupStr = groupController.text.trim();
                Navigator.pop(context, _AddFromRecipeResult(
                  ingredients: list,
                  group: groupStr.isEmpty ? null : groupStr,
                ));
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
    if (result == null || result.ingredients.isEmpty || !mounted) return;
    await ShoppingService.instance.addItemsFromRecipe(result.ingredients, group: result.group);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено: ${result.ingredients.length}')),
      );
    }
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
    await Share.share(text, subject: 'Список покупок');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка на список отправлена')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Список пуст',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Добавьте продукты вручную или из рецептов',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _addFromRecipe,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить из рецепта'),
                    ),
                  ],
                ),
              ),
            );
          }
          final grouped = ShoppingService.instance.getGrouped();
          final keys = grouped.keys.toList()
            ..sort((a, b) => _departmentOrder(a).compareTo(_departmentOrder(b)));

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                        title: Text(item.name),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => ShoppingService.instance.removeItem(item),
                        ),
                      )),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add_from_recipe',
            onPressed: _addFromRecipe,
            icon: const Icon(Icons.restaurant_menu),
            label: const Text('Из рецепта'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'add_manual',
            onPressed: () async {
              String? group;
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
                          onChanged: (v) => group = v.trim().isEmpty ? null : v.trim(),
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
                                group = g;
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
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
