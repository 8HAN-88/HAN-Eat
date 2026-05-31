import '../../models/recipe_category.dart';
import '../../services/subscription_service.dart';

/// Доступ к калориям и БЖУ на карточках и в фильтрах.
class RecipeNutritionAccess {
  RecipeNutritionAccess._();

  /// Теги Spoonacular, завязанные на нутриенты (не время/сложность).
  static const nutritionFilterTags = {'low-calorie', 'high-protein'};

  static bool isNutritionFilterTag(String tags) =>
      nutritionFilterTags.contains(tags.trim().toLowerCase());

  /// Категории с лимитами по БЖУ / калориям.
  static bool isNutritionCategory(RecipeCategory category) {
    switch (category) {
      case RecipeCategory.highProtein:
      case RecipeCategory.lowFat:
      case RecipeCategory.lowCarb:
        return true;
      default:
        return false;
    }
  }

  static bool fromSubscription(SubscriptionStatusResponse? status) {
    if (status == null) return false;
    if (!status.isActive && !status.inGracePeriod) return false;
    return status.isPlus ||
        status.hasAi ||
        status.hasCreator ||
        status.hasAnyPaid;
  }

  /// Резерв: флаг с API рекомендаций, если статус подписки ещё не загружен.
  static bool resolve({
    SubscriptionStatusResponse? subscription,
    bool viewerIsPlus = false,
  }) {
    if (fromSubscription(subscription)) return true;
    return viewerIsPlus;
  }
}
