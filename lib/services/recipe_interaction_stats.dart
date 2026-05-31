import 'package:flutter/foundation.dart';

/// Результат закрытия [DetailPage] — обновляет кэш карточек в «Меню».
class RecipeDetailPopResult {
  const RecipeDetailPopResult({
    required this.recipeId,
    required this.source,
    required this.commentCount,
    required this.avgRating,
    required this.ratingCount,
  });

  final int recipeId;
  final String source;
  final int commentCount;
  final double avgRating;
  final int ratingCount;
}

class RecipeInteractionSnapshot {
  const RecipeInteractionSnapshot({
    required this.commentCount,
    required this.avgRating,
    required this.ratingCount,
  });

  final int commentCount;
  final double avgRating;
  final int ratingCount;
}

/// Кэш счётчиков рецепта для карточек ленты «Меню» (после комментариев/оценок).
class RecipeInteractionStats {
  RecipeInteractionStats._();

  static final ValueNotifier<int> revision = ValueNotifier(0);
  static final Map<String, RecipeInteractionSnapshot> _cache = {};

  static String key(String source, int recipeId) => '$source:$recipeId';

  static RecipeInteractionSnapshot? snapshot(String source, int recipeId) {
    return _cache[key(source, recipeId)];
  }

  static void apply(RecipeDetailPopResult result) {
    _cache[key(result.source, result.recipeId)] = RecipeInteractionSnapshot(
      commentCount: result.commentCount,
      avgRating: result.avgRating,
      ratingCount: result.ratingCount,
    );
    revision.value++;
  }

  static void invalidate(String source, int recipeId) {
    if (_cache.remove(key(source, recipeId)) != null) {
      revision.value++;
    }
  }
}
