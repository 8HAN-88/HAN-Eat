import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/shopping_item.dart';

/// Список покупок хранится локально (Hive). Не очищается при выходе из аккаунта —
/// удаляется только по действию пользователя (кнопка «Очистить список»).
class ShoppingService {
  static late final ShoppingService instance;
  static const String _boxName = 'shopping_list';
  static const String _keyItems = 'items';
  late final Box _box;

  final ValueNotifier<List<ShoppingItem>> items = ValueNotifier(<ShoppingItem>[]);

  ShoppingService._internal(this._box) {
    _loadFromBox();
  }

  /// Загрузить список из хранилища (при старте и при открытии экрана).
  void _loadFromBox() {
    try {
      final raw = _box.get(_keyItems, defaultValue: <dynamic>[]);
      final List<dynamic> stored = raw is List ? raw : (raw != null ? [raw] : <dynamic>[]);
      items.value = stored.map((e) {
        if (e == null) return null;
        if (e is Map) {
          return ShoppingItem.fromJson(Map<String, dynamic>.from(e as Map));
        }
        final name = e.toString().trim();
        return name.isEmpty ? null : ShoppingItem(name: name, group: null);
      }).whereType<ShoppingItem>().where((e) => e.name.trim().isNotEmpty).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('ShoppingService _loadFromBox: $e');
      items.value = [];
    }
  }

  /// Перезагрузить из хранилища (вызвать при открытии экрана списка покупок).
  Future<void> reloadFromStorage() async {
    _loadFromBox();
  }

  static Future<void> init() async {
    final box = await Hive.openBox(_boxName);
    instance = ShoppingService._internal(box);
  }

  /// Список сгруппированный по подгруппам (null = "Без группы").
  Map<String?, List<ShoppingItem>> getGrouped() {
    final map = <String?, List<ShoppingItem>>{};
    for (final item in items.value) {
      final key = item.group == null || item.group!.isEmpty ? null : item.group;
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  Future<void> addItem(String name, {String? group}) async {
    final nameTrim = name.trim();
    if (nameTrim.isEmpty) return;
    if (items.value.any((e) => e.name == nameTrim && e.group == group)) return;
    items.value = [...items.value, ShoppingItem(name: nameTrim, group: group)];
    await _save();
  }

  Future<void> addItems(List<String> newItems, {String? group}) async {
    final toAdd = newItems
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .where((name) => !items.value.any((e) => e.name == name && e.group == group))
        .map((name) => ShoppingItem(name: name, group: group))
        .toList();
    if (toAdd.isEmpty) return;
    items.value = [...items.value, ...toAdd];
    await _save();
  }

  /// Добавить ингредиенты из рецепта в список (можно указать подгруппу).
  Future<void> addItemsFromRecipe(List<String> ingredients, {String? group}) async {
    await addItems(ingredients, group: group);
  }

  Future<void> removeItem(ShoppingItem item) async {
    items.value = items.value.where((e) => e.name != item.name || e.group != item.group).toList();
    await _save();
  }

  /// Очистить список. Вызывается только по явному действию пользователя.
  Future<void> clear() async {
    items.value = [];
    await _box.delete(_keyItems);
  }

  Future<void> _save() async {
    try {
      await _box.put(_keyItems, items.value.map((e) => e.toJson()).toList());
    } catch (e) {
      if (kDebugMode) debugPrint('ShoppingService _save: $e');
    }
  }

  Map<String, dynamic> exportToJson() {
    return {
      'items': items.value.map((e) => e.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> importFromJson(Map<String, dynamic> json, {bool merge = true}) async {
    final List<dynamic> raw = json['items'] as List<dynamic>? ?? [];
    final incoming = raw
        .map((e) {
          if (e is Map) return ShoppingItem.fromJson(Map<String, dynamic>.from(e as Map));
          return ShoppingItem(name: e.toString(), group: null);
        })
        .where((e) => e.name.trim().isNotEmpty)
        .toList();

    if (merge) {
      final seen = <String>{};
      for (final e in items.value) {
        seen.add('${e.name}|${e.group ?? ''}');
      }
      final toAdd = incoming.where((e) => !seen.contains('${e.name}|${e.group ?? ''}')).toList();
      items.value = [...items.value, ...toAdd];
    } else {
      items.value = incoming;
    }
    await _save();
  }

  Future<void> importFromJsonString(String jsonString, {bool merge = true}) async {
    final Map<String, dynamic> map = json.decode(jsonString) as Map<String, dynamic>;
    await importFromJson(map, merge: merge);
  }

  /// Текст списка для шаринга (по группам).
  String toShareableText() {
    final grouped = getGrouped();
    final keys = grouped.keys.toList()..sort((a, b) => (a ?? '').compareTo(b ?? ''));
    final sb = StringBuffer();
    for (final key in keys) {
      final label = key == null || key.isEmpty ? 'Без группы' : key;
      sb.writeln('$label:');
      for (final item in grouped[key]!) {
        sb.writeln('  • ${item.name}');
      }
      sb.writeln();
    }
    return sb.toString().trim();
  }
}
