import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/subscription_service.dart';
import '../../../services/subscription_status_cache.dart';

/// Счётчик для принудительного обновления [subscriptionStatusProvider].
final subscriptionStatusRefreshProvider = StateProvider<int>((ref) => 0);

/// true — последний запрос статуса не удался, показан кэш.
final subscriptionStatusFromCacheProvider = StateProvider<bool>((ref) => false);

/// Статус подписки с бэкенда (кэш через FutureProvider + ручной refresh).
final subscriptionStatusProvider =
    FutureProvider<SubscriptionStatusResponse?>((ref) async {
  ref.watch(subscriptionStatusRefreshProvider);
  final cached =
      SubscriptionStatusCache.peek() ?? await SubscriptionStatusCache.load();
  try {
    final status = await SubscriptionService.getSubscriptionStatus();
    await SubscriptionStatusCache.save(status);
    ref.read(subscriptionStatusFromCacheProvider.notifier).state = false;
    return status;
  } catch (_) {
    ref.read(subscriptionStatusFromCacheProvider.notifier).state =
        cached != null;
    return cached;
  }
});

void refreshSubscriptionStatus(WidgetRef ref) {
  ref.read(subscriptionStatusRefreshProvider.notifier).state++;
}

final hasProSubscriptionProvider = Provider<bool>((ref) {
  final status = ref.watch(subscriptionStatusProvider);
  final current = status.valueOrNull ?? SubscriptionStatusCache.peek();
  return current?.hasPro ?? false;
});
