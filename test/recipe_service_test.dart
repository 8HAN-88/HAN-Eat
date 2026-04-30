import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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

  test('RecipeService manualSync populates cache', () async {
    await RecipeService.init();
    final svc = RecipeService.instance;

    // initial may be empty; force a manual sync (uses mock if API key absent)
    await svc.manualSync();

    expect(svc.recipes.value, isA<List<RecipeModel>>());
    expect(svc.recipes.value.length, greaterThanOrEqualTo(1));
  });

  test('RecipeService searchRemoteAndCache (mock or API)', () async {
    await RecipeService.init();
    final svc = RecipeService.instance;

    // remote search with likely empty API key will fallback to mock; ensure no error
    await svc.searchRemoteAndCache('pasta');
    expect(svc.recipes.value, isNotNull);
  });
}
