import 'dart:async';

import 'package:flutter/services.dart';

/// Лёгкая обратная связь без дублирования вызовов по всему приложению.
abstract final class AppHaptics {
  static void selection() => unawaited(HapticFeedback.selectionClick());

  static void light() => unawaited(HapticFeedback.lightImpact());

  static void medium() => unawaited(HapticFeedback.mediumImpact());
}
