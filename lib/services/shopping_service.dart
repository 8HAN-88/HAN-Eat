import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/shopping_item.dart';
import '../utils/ingredient_quantity.dart';

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
          return ShoppingItem.fromJson(Map<String, dynamic>.from(e));
        }
        final line = e.toString().trim();
        if (line.isEmpty) return null;
        final parsed = parseIngredientLine(line);
        return ShoppingItem(
          name: parsed.name,
          quantity: parsed.displayQuantity,
        );
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

  String _identityKey(ShoppingItem item) =>
      '${item.name.trim().toLowerCase()}|${item.group ?? ''}|${item.quantity ?? ''}';

  ShoppingItem? _findMatching(String name, {String? group, String? quantity}) {
    final key = '${name.trim().toLowerCase()}|${group ?? ''}|${quantity ?? ''}';
    for (final e in items.value) {
      if (_identityKey(e) == key) return e;
    }
    return null;
  }

  Future<void> addItem(String name, {String? group, String? quantity}) async {
    final parsed = parseIngredientLine(name);
    final productName = parsed.name.isNotEmpty ? parsed.name : name.trim();
    final qty = quantity ?? parsed.displayQuantity;
    if (productName.isEmpty) return;
    await _addOrMerge(
      name: productName,
      quantity: qty,
      group: group,
    );
  }

  Future<void> addItems(List<String> newItems, {String? group}) async {
    for (final line in newItems) {
      await addItem(line, group: group);
    }
  }

  /// Добавить позиции с отдельным полем количества (AI-план, импорт).
  Future<void> addCatalogItems(
    List<({String name, String? quantity})> catalog, {
    String? group,
  }) async {
    for (final row in catalog) {
      if (row.name.trim().isEmpty) continue;
      await _addOrMerge(
        name: row.name.trim(),
        quantity: row.quantity?.trim().isEmpty == true ? null : row.quantity?.trim(),
        group: group,
      );
    }
  }

  /// Добавить ингредиенты из рецепта: парсинг г/шт и объединение.
  Future<void> addItemsFromRecipe(List<String> ingredients, {String? group}) async {
    final merged = mergeIngredientLines(ingredients);
    await addCatalogItems(merged, group: group);
  }

  Future<void> _addOrMerge({
    required String name,
    String? quantity,
    String? group,
  }) async {
    final existing = _findMatching(name, group: group, quantity: quantity);
    if (existing != null) return;

    // Попытка слить с той же позицией без количества / с совместимым количеством
    final parsedNew = parseIngredientLine(
      quantity != null ? '$name $quantity' : name,
    );
    final list = [...items.value];
    var merged = false;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e.group != group) continue;
      if (e.name.trim().toLowerCase() != name.trim().toLowerCase()) continue;
      final parsedOld = parseIngredientLine(
        e.quantity != null ? '${e.name} ${e.quantity}' : e.name,
      );
      if (parsedNew.amount != null &&
          parsedOld.amount != null &&
          parsedNew.unit == parsedOld.unit) {
        final sum = parsedOld.amount! + parsedNew.amount!;
        list[i] = e.copyWith(
          quantity: ParsedIngredient(
            name: e.name,
            amount: sum,
            unit: parsedOld.unit,
          ).displayQuantity,
        );
        merged = true;
        break;
      }
      if (parsedNew.amount == null &&
          parsedOld.amount == null &&
          e.quantity == null &&
          quantity == null) {
        continue;
      }
    }
    if (!merged) {
      list.add(ShoppingItem(name: name.trim(), quantity: quantity, group: group));
    }
    items.value = list;
    await _save();
  }

  Future<void> removeItem(ShoppingItem item) async {
    items.value =
        items.value.where((e) => !e.sameIdentityAs(item)).toList();
    await _save();
  }

  Future<void> togglePurchased(ShoppingItem item, bool purchased) async {
    items.value = items.value
        .map(
          (e) => e.sameIdentityAs(item) ? e.copyWith(purchased: purchased) : e,
        )
        .toList();
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
          if (e is Map) return ShoppingItem.fromJson(Map<String, dynamic>.from(e));
          return ShoppingItem(name: e.toString(), group: null);
        })
        .where((e) => e.name.trim().isNotEmpty)
        .toList();

    if (merge) {
      for (final e in incoming) {
        await _addOrMerge(name: e.name, quantity: e.quantity, group: e.group);
      }
    } else {
      items.value = incoming;
      await _save();
    }
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
        final qty = item.quantity;
        sb.writeln(
          qty != null && qty.isNotEmpty
              ? '  • ${item.name} — $qty'
              : '  • ${item.name}',
        );
      }
      sb.writeln();
    }
    return sb.toString().trim();
  }
}
