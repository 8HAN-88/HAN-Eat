import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/subscription/recipe_nutrition_access.dart';
import '../../../services/subscription_service.dart';

/// Счётчик для принудительного обновления [subscriptionStatusProvider].
final subscriptionStatusRefreshProvider = StateProvider<int>((ref) => 0);

/// Статус подписки с бэкенда (кэш через FutureProvider + ручной refresh).
final subscriptionStatusProvider =
    FutureProvider<SubscriptionStatusResponse?>((ref) async {
  ref.watch(subscriptionStatusRefreshProvider);
  try {
    return await SubscriptionService.getSubscriptionStatus();
  } catch (_) {
    return null;
  }
});

void refreshSubscriptionStatus(WidgetRef ref) {
  ref.read(subscriptionStatusRefreshProvider.notifier).state++;
}

/// Калории и БЖУ доступны подписчикам (AI / Creator / Pro).
final canViewRecipeNutritionProvider = Provider<bool>((ref) {
  final status = ref.watch(subscriptionStatusProvider);
  return status.when(
    data: RecipeNutritionAccess.fromSubscription,
    loading: () => false,
    error: (_, __) => false,
  );
});
