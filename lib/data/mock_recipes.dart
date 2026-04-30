import '../models/recipe_model.dart';

class Recipe {
  final String id;
  final String title;
  final int cookTime;
  final List<String> ingredients;
  final List<String> steps;
  final String? image;

  Recipe({
    required this.id,
    required this.title,
    required this.cookTime,
    required this.ingredients,
    required this.steps,
    this.image,
  });
}

final mockRecipes = [
  Recipe(
    id: '1',
    title: 'Tomato Pasta',
    cookTime: 20,
    ingredients: ['pasta', 'tomato', 'garlic', 'olive oil', 'salt'],
    steps: ['Boil pasta', 'Prepare tomato sauce', 'Mix and serve'],
    image: 'https://picsum.photos/seed/pasta/800/400',
  ),
  Recipe(
    id: '2',
    title: 'Avocado Toast',
    cookTime: 10,
    ingredients: ['bread', 'avocado', 'salt', 'pepper'],
    steps: ['Toast bread', 'Mash avocado', 'Spread and serve'],
    image: 'https://picsum.photos/seed/toast/800/400',
  ),
  Recipe(
    id: '3',
    title: 'Omelette',
    cookTime: 8,
    ingredients: ['eggs', 'salt', 'butter', 'cheese'],
    steps: ['Beat eggs', 'Cook in pan', 'Fold and serve'],
    image: 'https://picsum.photos/seed/omelette/800/400',
  ),
];

List<RecipeModel> getMockRecipeModels() {
  final now = DateTime.now();
  return mockRecipes
      .map((r) => RecipeModel(
            id: r.id,
            title: r.title,
            cookTime: r.cookTime,
            ingredients: r.ingredients,
            steps: r.steps,
            image: r.image,
            updatedAt: now,
          ))
      .toList();
}
