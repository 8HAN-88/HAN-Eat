import 'package:flutter/material.dart';

/// Базовые UI-токены, чтобы радиусы и отступы не расходились по экранам.
class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double input = 18;
  static const double card = 22;
  static const double sheet = 26;
  static const double nav = 28;
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppInsets {
  const AppInsets._();

  static const EdgeInsets screen = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets card = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: 14,
  );
}

class AppSizes {
  const AppSizes._();

  /// Компактная плавающая панель (ближе к Telegram).
  static const double floatingNavHeight = 52;
  static const double floatingNavSearchSize = 52;
}
