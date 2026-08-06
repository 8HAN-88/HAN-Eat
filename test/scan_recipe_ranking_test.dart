import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/kitchen/menu/scan_recipe_ranking.dart';
import 'package:han_eat/features/kitchen/data/models/recipe.dart';

Recipe _spoon(int id, String title) => Recipe(
      id: id,
      title: title,
      translatedTitle: title,
      image: 'https://example.com/$id.jpg',
      usedIngredientCount: 0,
      ingredients: const [],
      steps: const [],
      source: 'spoonacular',
    );

void main() {
  test('filterForScan drops unrelated Spoonacular when dish is pizza', () {
    final recipes = [
      _spoon(1, 'Black Bean and Veggie Burgers'),
      _spoon(2, 'Classic Margherita Pizza'),
      _spoon(3, 'Lemon Lentil Soup'),
    ];
    final out = ScanRecipeRanking.filterForScan(recipes, 'pizza');
    expect(out.length, 1);
    expect(out.first.title.toLowerCase(), contains('pizza'));
  });

  test('filterForScan returns empty when nothing matches', () {
    final recipes = [
      _spoon(1, 'Black Bean and Veggie Burgers'),
      _spoon(2, 'Edamame Snack'),
    ];
    final out = ScanRecipeRanking.filterForScan(recipes, 'pizza');
    expect(out, isEmpty);
  });
}
