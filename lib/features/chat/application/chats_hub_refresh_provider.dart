import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Инкремент — перезагрузить список «Чаты» (вкладка «Все»).
final chatsHubRefreshProvider = StateProvider<int>((ref) => 0);

void refreshChatsHub(WidgetRef ref) {
  ref.read(chatsHubRefreshProvider.notifier).state++;
}
