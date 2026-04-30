import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:han_eat/models/recipe_model.dart';

void main() {
  late Directory tmpDir;
  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('han_eat_test_hive_');
    Hive.init(tmpDir.path);
    if (!Hive.isAdapterRegistered(RecipeModelAdapter().typeId)) {
      Hive.registerAdapter(RecipeModelAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  test('RecipeModelAdapter write/read from box', () async {
    final box = await Hive.openBox('test_recipes_box');
    final now = DateTime.now();
    final model = RecipeModel(
      id: 'x1',
      title: 'Hive Dish',
      cookTime: 5,
      ingredients: ['i1'],
      steps: ['s1'],
      image: null,
      updatedAt: now,
    );

    await box.put(model.id, model);
    final loaded = box.get(model.id) as RecipeModel?;

    expect(loaded, isNotNull);
    expect(loaded!.id, model.id);
    expect(loaded.title, model.title);
    await box.clear();
    await box.close();
  });
}
