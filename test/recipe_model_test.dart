import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/recipe_model.dart';

void main() {
  test('RecipeModel toMap/fromMap roundtrip', () {
    final now = DateTime.now();
    final model = RecipeModel(
      id: 'r1',
      title: 'Test Dish',
      cookTime: 12,
      ingredients: ['a', 'b'],
      steps: ['step1'],
      image: 'https://example.com/img.png',
      updatedAt: now,
    );

    final map = model.toMap();
    final restored = RecipeModel.fromMap(map);

    expect(restored.id, model.id);
    expect(restored.title, model.title);
    expect(restored.cookTime, model.cookTime);
    expect(restored.ingredients, model.ingredients);
    expect(restored.steps, model.steps);
    expect(restored.image, model.image);
    // compare by date string / presence
    expect(restored.updatedAt.toIso8601String().substring(0, 19),
        model.updatedAt.toIso8601String().substring(0, 19));
  });
}
