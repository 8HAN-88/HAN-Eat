import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Скрывает верхнюю панель [MainFeedScreen] при прокрутке ленты вниз.
final feedScrollChromeHidden = ValueNotifier<bool>(false);

/// Компактная нижняя панель [RootShell] при прокрутке вниз (как в Instagram).
final shellNavCompact = ValueNotifier<bool>(false);

/// Активно только на вкладках «Подписки» / «Рекомендации» (не на рилсах).
final feedScrollChromeActive = ValueNotifier<bool>(true);

const Duration kFeedScrollChromeDuration = Duration(milliseconds: 260);
const Duration kShellNavCompactDuration = Duration(milliseconds: 220);
const Duration kShellNavExpandDuration = Duration(milliseconds: 90);
const Curve kFeedScrollChromeCurve = Curves.easeOutCubic;
const Curve kShellNavChromeCurve = Curves.easeOutCubic;

const double _kScrollDeltaThreshold = 6;
const double _kMinOffsetToHide = 48;

/// Высота верхней панели ленты: вкладки + уведомления (одна строка).
const double kFeedChromeHeaderHeight = 50;

/// Полная высота плавающей нижней панели в [RootShell].
const double kShellNavExpandedHeight = 62;

/// Компактная высота нижней панели при прокрутке вниз.
const double kShellNavCompactHeight = 50;

/// Отступ панели от нижнего края (как в Instagram).
const double kShellNavBottomMarginExpanded = 16;
const double kShellNavBottomMarginCompact = 12;
const double kShellNavSideMargin = 24;

double feedChromeTopInset(BuildContext context) {
  final top = MediaQuery.paddingOf(context).top;
  return top + kFeedChromeHeaderHeight;
}

void _setFeedScrollChromeHidden(bool hidden) {
  if (feedScrollChromeHidden.value == hidden) return;
  void apply() {
    if (feedScrollChromeHidden.value != hidden) {
      feedScrollChromeHidden.value = hidden;
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

void _setShellNavCompact(bool compact) {
  if (shellNavCompact.value == compact) return;
  void apply() {
    if (shellNavCompact.value != compact) {
      shellNavCompact.value = compact;
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

void resetFeedScrollChrome() {
  _setFeedScrollChromeHidden(false);
}

void resetShellNavCompact() {
  _setShellNavCompact(false);
}

bool _handleScrollCompactNotification(
  ScrollNotification notification, {
  required void Function(bool compact) setCompact,
  bool enabled = true,
}) {
  if (!enabled) return false;

  final metrics = notification.metrics;
  if (!metrics.hasViewportDimension) return false;
  if (metrics.axis != Axis.vertical) return false;

  if (metrics.pixels <= 16) {
    setCompact(false);
    return false;
  }

  if (notification is ScrollUpdateNotification) {
    final delta = notification.scrollDelta;
    if (delta == null) return false;

    if (delta > _kScrollDeltaThreshold && metrics.pixels > _kMinOffsetToHide) {
      setCompact(true);
    } else if (delta < -_kScrollDeltaThreshold) {
      setCompact(false);
    }
  }

  return false;
}

bool handleFeedScrollNotification(ScrollNotification notification) {
  return _handleScrollCompactNotification(
    notification,
    setCompact: _setFeedScrollChromeHidden,
    enabled: feedScrollChromeActive.value,
  );
}

bool handleShellNavScrollNotification(ScrollNotification notification) {
  return _handleScrollCompactNotification(
    notification,
    setCompact: _setShellNavCompact,
  );
}

/// Прокидывает [ScrollNotification] в [handleFeedScrollNotification].
class FeedScrollChromeListener extends StatelessWidget {
  const FeedScrollChromeListener({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: handleFeedScrollNotification,
      child: child,
    );
  }
}

/// Прокидывает [ScrollNotification] в [handleShellNavScrollNotification].
class ShellScrollChromeListener extends StatelessWidget {
  const ShellScrollChromeListener({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: handleShellNavScrollNotification,
      child: child,
    );
  }
}
