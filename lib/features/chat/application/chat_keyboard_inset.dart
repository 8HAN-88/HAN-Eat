/// Flutter web / iOS PWA reports visual-viewport chrome (toolbar, rubber-band)
/// as tiny [viewInsets]. Animating the whole thread on that noise shakes the
/// chat when the user reaches the bottom.
///
/// [viewportResizesContent] is true when the HTML viewport uses
/// `interactive-widget=resizes-content` — the layout viewport already shrinks
/// with the keyboard, so manual padding must stay zero to avoid a gap.
double effectiveChatKeyboardInset({
  required double rawInset,
  required bool composerFocused,
  bool viewportResizesContent = false,
}) {
  if (viewportResizesContent) return 0;
  // While typing, follow the keyboard frame-by-frame (Safari animates ~250ms).
  // Thresholds below are only for unfocused rubber-band noise.
  if (composerFocused) return rawInset < 0 ? 0 : rawInset;
  if (rawInset < 80) return 0;
  if (rawInset < 140) return 0;
  return rawInset;
}

/// True when the list is close enough to the latest messages.
///
/// [reversed] matches Flutter `ListView(reverse: true)` — latest is offset 0.
bool chatScrollIsNearBottom({
  required double offset,
  required double maxScrollExtent,
  double threshold = 120,
  bool reversed = false,
}) {
  if (reversed) return offset <= threshold;
  return maxScrollExtent - offset <= threshold;
}

/// Distance from the latest messages (0 = pinned to last).
double chatDistanceFromLatest({
  required double offset,
  required double maxScrollExtent,
  bool reversed = false,
}) {
  if (reversed) return offset;
  return maxScrollExtent - offset;
}

/// Hysteresis so the jump-FAB does not blink while iOS bounces at the end.
enum ChatBottomFabPolicy { hide, show, keep }

ChatBottomFabPolicy chatBottomFabPolicy({
  required double offset,
  required double maxScrollExtent,
  double hideBelow = 80,
  double showAbove = 180,
  bool reversed = false,
}) {
  final distance = chatDistanceFromLatest(
    offset: offset,
    maxScrollExtent: maxScrollExtent,
    reversed: reversed,
  );
  if (distance <= hideBelow) return ChatBottomFabPolicy.hide;
  if (distance > showAbove) return ChatBottomFabPolicy.show;
  return ChatBottomFabPolicy.keep;
}

/// Scroll so a bubble moves [delta] px toward the top of the screen.
/// Reverse lists move the other way (latest is offset 0).
double chatOverlayScrollTarget({
  required double offset,
  required double maxScrollExtent,
  required double delta,
  bool reversed = false,
}) {
  final next = reversed ? offset - delta : offset + delta;
  if (next < 0) return 0;
  if (next > maxScrollExtent) return maxScrollExtent;
  return next;
}
