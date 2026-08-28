/// Flutter web / iOS PWA reports visual-viewport chrome (toolbar, rubber-band)
/// as tiny [viewInsets]. Animating the whole thread on that noise shakes the
/// chat when the user reaches the bottom.
double effectiveChatKeyboardInset({
  required double rawInset,
  required bool composerFocused,
}) {
  if (rawInset < 80) return 0;
  if (!composerFocused && rawInset < 140) return 0;
  return rawInset;
}

/// True when the list is close enough to the latest messages.
bool chatScrollIsNearBottom({
  required double offset,
  required double maxScrollExtent,
  double threshold = 120,
}) {
  return maxScrollExtent - offset <= threshold;
}

/// Hysteresis so the jump-FAB does not blink while iOS bounces at the end.
enum ChatBottomFabPolicy { hide, show, keep }

ChatBottomFabPolicy chatBottomFabPolicy({
  required double offset,
  required double maxScrollExtent,
  double hideBelow = 80,
  double showAbove = 180,
}) {
  final distance = maxScrollExtent - offset;
  if (distance <= hideBelow) return ChatBottomFabPolicy.hide;
  if (distance > showAbove) return ChatBottomFabPolicy.show;
  return ChatBottomFabPolicy.keep;
}
