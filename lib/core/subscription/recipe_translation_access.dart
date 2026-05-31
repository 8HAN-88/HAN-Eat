import '../../services/subscription_service.dart';

/// Перевод рецептов Spoonacular на язык из настроек — тариф AI / Pro.
class RecipeTranslationAccess {
  RecipeTranslationAccess._();

  static bool fromSubscription(SubscriptionStatusResponse? status) {
    if (status == null) return false;
    if (!status.isActive && !status.inGracePeriod) return false;
    return status.hasAi;
  }
}
