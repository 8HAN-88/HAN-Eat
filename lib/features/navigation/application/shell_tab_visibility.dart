import 'package:flutter/foundation.dart';

/// Активная вкладка нижней панели (0=лента, 1=чаты, 2=меню, 3=профиль).
/// Тяжёлые экраны (чаты) не грузят API, пока вкладка не открыта.
class ShellTabVisibility {
  ShellTabVisibility._();

  static final ValueNotifier<int> activeIndex = ValueNotifier<int>(0);

  static bool get chatsActive => activeIndex.value == 1;
}
