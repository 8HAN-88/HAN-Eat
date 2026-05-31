import '../../models/recipe.dart';

/// Ранжирование и фильтрация рецептов для экрана AI-скана.
class ScanRecipeRanking {
  ScanRecipeRanking._();

  static bool isCommunityRecipe(Recipe recipe) {
    final src = recipe.source?.toLowerCase();
    return src == 'user' || src == 'channel';
  }

  /// Рецепты HAN Eat: база, профиль, каналы (не Spoonacular).
  static bool isLocalRecipe(Recipe recipe) {
    final src = recipe.source?.toLowerCase();
    if (src == 'base' || src == 'user' || src == 'channel') return true;
    final idStr = '${recipe.id}';
    return idStr.startsWith('base_') ||
        idStr.startsWith('user_') ||
        idStr.startsWith('channel_');
  }

  static bool isSpoonacularRecipe(Recipe recipe) {
    if (isLocalRecipe(recipe)) return false;
    if (recipe.source?.toLowerCase() == 'spoonacular') return true;
    return recipe.id > 0;
  }

  static String _norm(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ').trim();

  static List<String> _words(String value) => _norm(value)
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 3)
      .toList();

  /// Совпадение названия блюда с рецептом (для фильтра «похожих»).
  static bool recipeMatchesDish(Recipe recipe, String dishLabel) {
    final dish = _norm(dishLabel);
    if (dish.isEmpty) return false;
    final title = _norm(recipe.translatedTitle ?? recipe.title);
    if (title.isEmpty) return false;
    if (title.contains(dish) || dish.contains(title)) return true;

    final dishWords = _words(dish);
    final titleWords = _words(title);
    if (dishWords.isEmpty || titleWords.isEmpty) return false;

    var hits = 0;
    for (final dw in dishWords) {
      if (titleWords.any((tw) => tw.contains(dw) || dw.contains(tw))) {
        hits++;
      }
    }
    return hits >= 1 && hits >= (dishWords.length / 2).ceil();
  }

  static int _relevanceScore(Recipe recipe, String dishLabel) {
    var score = 0;
    if (recipeMatchesDish(recipe, dishLabel)) score += 100;
    if (isSpoonacularRecipe(recipe)) score += 40;
    if (recipe.nutrition != null && recipe.nutrition!.isNotEmpty) score += 20;
    if (recipe.calories != null) score += 10;
    score += recipe.usedIngredientCount;
    return score;
  }

  /// Убирает нерелевантные посты сообщества; сортирует по близости к распознанному блюду.
  static List<Recipe> filterForScan(List<Recipe> recipes, String dishLabel) {
    if (recipes.isEmpty) return recipes;

    final label = dishLabel.trim();
    if (label.isEmpty) {
      final localOnly = recipes.where(isLocalRecipe).toList();
      if (localOnly.isNotEmpty) return localOnly.take(8).toList();
      return const [];
    }
    final matched = <Recipe>[];
    final local = <Recipe>[];
    final spoonacular = <Recipe>[];

    for (final recipe in recipes) {
      if (isLocalRecipe(recipe)) {
        if (label.isEmpty || recipeMatchesDish(recipe, label)) {
          local.add(recipe);
        }
        continue;
      }
      if (label.isNotEmpty && recipeMatchesDish(recipe, label)) {
        matched.add(recipe);
      } else if (isSpoonacularRecipe(recipe)) {
        spoonacular.add(recipe);
      }
    }

    int sortScore(Recipe r) => _relevanceScore(r, label);
    matched.sort((a, b) => sortScore(b).compareTo(sortScore(a)));
    local.sort((a, b) => sortScore(b).compareTo(sortScore(a)));
    spoonacular.sort((a, b) => sortScore(b).compareTo(sortScore(a)));

    if (matched.isNotEmpty) {
      return [...matched, ...local].take(10).toList();
    }

    if (local.isNotEmpty) {
      return local.take(8).toList();
    }

    final relevantSpoon = spoonacular
        .where((r) => recipeMatchesDish(r, label))
        .toList();
    if (relevantSpoon.isNotEmpty) return relevantSpoon.take(10).toList();

    if (label.isNotEmpty && spoonacular.isNotEmpty) {
      return spoonacular.take(6).toList();
    }

    return const [];
  }

  /// Источник калорий/БЖУ: сначала совпадение по названию, затем Spoonacular.
  static Recipe? pickNutritionSource(
    List<Recipe> recipes,
    String dishLabel,
  ) {
    if (recipes.isEmpty) return null;

    Recipe? best;
    var bestScore = -1;

    for (final recipe in recipes) {
      if (recipe.calories == null &&
          (recipe.nutrition == null || recipe.nutrition!.isEmpty)) {
        continue;
      }

      var score = _relevanceScore(recipe, dishLabel);
      if (isLocalRecipe(recipe) && !recipeMatchesDish(recipe, dishLabel)) {
        continue;
      }

      // Подозрительно высокие калории у чужого поста (часто дневная норма, не порция).
      final c = recipe.calories;
      if (c != null && c > 1200 && isCommunityRecipe(recipe)) {
        score -= 50;
      }

      if (score > bestScore) {
        bestScore = score;
        best = recipe;
      }
    }

    return best;
  }

  static num? extractCalories(List<Recipe> recipes, String dishLabel) {
    return pickNutritionSource(recipes, dishLabel)?.calories;
  }

  static Map<String, dynamic>? extractNutrition(
    List<Recipe> recipes,
    String dishLabel,
  ) {
    final n = pickNutritionSource(recipes, dishLabel)?.nutrition;
    if (n != null && n.isNotEmpty) return n;
    return null;
  }

}
