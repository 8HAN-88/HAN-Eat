import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Скрывает верхнюю панель [MainFeedScreen] и нижнюю [NavigationBar] при прокрутке ленты вниз.
final feedScrollChromeHidden = ValueNotifier<bool>(false);

/// Активно только на вкладках «Подписки» / «Рекомендации» (не на рилсах).
final feedScrollChromeActive = ValueNotifier<bool>(true);

const Duration kFeedScrollChromeDuration = Duration(milliseconds: 260);
const Curve kFeedScrollChromeCurve = Curves.easeOutCubic;

const double _kScrollDeltaThreshold = 6;
const double _kMinOffsetToHide = 48;

/// Высота верхней панели ленты: вкладки + уведомления (одна строка).
const double kFeedChromeHeaderHeight = 50;

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

void resetFeedScrollChrome() {
  _setFeedScrollChromeHidden(false);
}

bool handleFeedScrollNotification(ScrollNotification notification) {
  if (!feedScrollChromeActive.value) return false;

  final metrics = notification.metrics;
  if (!metrics.hasViewportDimension) return false;

  if (metrics.pixels <= 16) {
    _setFeedScrollChromeHidden(false);
    return false;
  }

  if (notification is ScrollUpdateNotification) {
    final delta = notification.scrollDelta;
    if (delta == null) return false;

    if (delta > _kScrollDeltaThreshold &&
        metrics.pixels > _kMinOffsetToHide) {
      _setFeedScrollChromeHidden(true);
    } else if (delta < -_kScrollDeltaThreshold) {
      _setFeedScrollChromeHidden(false);
    }
  }

  return false;
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
