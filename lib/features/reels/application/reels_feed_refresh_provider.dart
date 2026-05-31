import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Инкремент после публикации рилса — [ReelsFeedScreen] перезагружает ленту.
final reelsFeedRefreshProvider = StateProvider<int>((ref) => 0);

void notifyReelsFeedRefresh(WidgetRef ref) {
  ref.read(reelsFeedRefreshProvider.notifier).state++;
}
