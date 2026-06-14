import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:han_eat/data/mock_recipes.dart';
import 'package:han_eat/models/recipe_model.dart';
import 'package:han_eat/services/recipe_service.dart';

void main() {
  late Directory tmpDir;
  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('han_eat_test_recipe_');
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

  test('RecipeService caches mock recipes', () async {
    await RecipeService.init();
    final svc = RecipeService.instance;

    await svc.cacheRecipes(getMockRecipeModels());

    expect(svc.recipes.value, isA<List<RecipeModel>>());
    expect(svc.recipes.value.length, greaterThanOrEqualTo(1));
  });

  test('RecipeService searchRemoteAndCache (mock or API)', () async {
    await RecipeService.init();
    final svc = RecipeService.instance;

    await svc.searchRemoteAndCache('pasta');
    expect(svc.recipes.value, isNotNull);
  });
}
