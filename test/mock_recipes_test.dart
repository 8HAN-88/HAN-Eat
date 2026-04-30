import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/data/mock_recipes.dart';
import 'package:han_eat/models/recipe_model.dart';

void main() {
  test('getMockRecipeModels returns models matching mockRecipes length', () {
    final models = getMockRecipeModels();
    expect(models, isA<List<RecipeModel>>());
    expect(models.length, mockRecipes.length);
    for (final m in models) {
      expect(m.id, isNotEmpty);
      expect(m.title, isNotEmpty);
    }
  });
}
