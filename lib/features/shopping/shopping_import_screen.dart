import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/shopping_item.dart';
import '../../services/shopping_service.dart';
import '../../app/app_router.dart';

/// Экран импорта списка покупок по ссылке (haneat://shopping/import?data=...).
/// Пользователь видит список и может добавить его в свой список в приложении.
class ShoppingImportScreen extends StatefulWidget {
  const ShoppingImportScreen({super.key, required this.dataBase64});

  final String? dataBase64;

  @override
  State<ShoppingImportScreen> createState() => _ShoppingImportScreenState();
}

class _ShoppingImportScreenState extends State<ShoppingImportScreen> {
  List<ShoppingItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _decode() {
    final data = widget.dataBase64;
    if (data == null || data.isEmpty) {
      setState(() => _error = 'Нет данных для импорта');
      return;
    }
    try {
      final decoded = utf8.decode(base64.decode(data));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final list = json['items'] as List<dynamic>? ?? [];
      setState(() {
        _items = list
            .map((e) => ShoppingItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((e) => e.name.trim().isNotEmpty)
            .toList();
        _error = _items!.isEmpty ? 'Список пуст' : null;
      });
    } catch (e) {
      setState(() => _error = 'Не удалось прочитать список');
    }
  }

  Future<void> _addToMyList() async {
    if (_items == null || _items!.isEmpty) return;
    await ShoppingService.instance.importFromJson({
      'items': _items!.map((e) => e.toJson()).toList(),
    }, merge: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено ${_items!.length} позиций в ваш список')),
    );
    context.go(ShoppingListRoute.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Импорт списка')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => context.go(FeedRoute.path),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_items == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Список покупок'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(FeedRoute.path),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Вам поделились списком из ${_items!.length} позиций. Добавьте его в свой список в приложении.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items!.length,
              itemBuilder: (context, i) {
                final item = _items![i];
                return ListTile(
                  leading: const Icon(Icons.check_box_outlined),
                  title: Text(item.name),
                  subtitle: item.group != null ? Text(item.group!) : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _addToMyList,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Добавить в мой список покупок'),
            ),
          ),
        ],
      ),
    );
  }
}
