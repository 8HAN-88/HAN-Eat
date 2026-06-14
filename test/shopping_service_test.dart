import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:han_eat/models/shopping_item.dart';
import 'package:han_eat/services/shopping_service.dart';

void main() {
  late Directory tmpDir;
  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('han_eat_test_shop_');
    Hive.init(tmpDir.path);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('ShoppingService add/remove/clear & export/import', () async {
    await ShoppingService.init();
    final svc = ShoppingService.instance;
    List<String> names() => svc.items.value.map((e) => e.name).toList();

    expect(svc.items.value, isEmpty);

    await svc.addItems(['apple', 'banana']);
    expect(names(), containsAll(['apple', 'banana']));

    await svc.removeItem(const ShoppingItem(name: 'apple'));
    expect(names(), isNot(contains('apple')));

    final exported = svc.exportToJson();
    expect(exported['items'], isA<List>());

    // import replace
    await svc.importFromJson({
      'items': ['x', 'y']
    }, merge: false);
    expect(names(), containsAll(['x', 'y']));
  });
}
