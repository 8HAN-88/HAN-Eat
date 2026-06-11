import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Скрывает плавающую нижнюю [NavigationBar] в [RootShell] (полноэкранные рилсы).
final rootShellHideBottomNav = ValueNotifier<bool>(false);

void _setRootShellHideBottomNav(bool hide) {
  if (rootShellHideBottomNav.value == hide) return;
  void apply() {
    if (rootShellHideBottomNav.value != hide) {
      rootShellHideBottomNav.value = hide;
    }
  }

  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.idle ||
      phase == SchedulerPhase.postFrameCallbacks) {
    apply();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => apply());
}

void syncRootShellBottomNavForReels({
  required bool embeddedInShell,
  required bool tabVisible,
}) {
  _setRootShellHideBottomNav(embeddedInShell && tabVisible);
}

void clearRootShellBottomNavHide() {
  _setRootShellHideBottomNav(false);
}
