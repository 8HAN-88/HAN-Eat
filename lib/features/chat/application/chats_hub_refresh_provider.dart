import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Инкремент — перезагрузить список «Чаты» (вкладка «Все»).
final chatsHubRefreshProvider = StateProvider<int>((ref) => 0);

/// Запросить вкладку хаба (0 — чаты, 1 — контакты) после `go(/chats)`.
final chatsHubRequestedTab = ValueNotifier<int?>(null);

void refreshChatsHub(WidgetRef ref) {
  ref.read(chatsHubRefreshProvider.notifier).state++;
}

void requestChatsHubTab(int index) {
  chatsHubRequestedTab.value = index;
}
