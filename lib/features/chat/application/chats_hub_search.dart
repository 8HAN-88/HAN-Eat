import 'package:flutter/foundation.dart';

/// Сигнал открыть строку поиска на экране «Чаты» (кнопка в нижней панели).
final chatsHubSearchOpenRequest = ValueNotifier<int>(0);

void requestChatsHubSearchOpen() {
  chatsHubSearchOpenRequest.value++;
}
