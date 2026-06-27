import 'package:flutter/material.dart';

/// Базовые UI-токены, чтобы радиусы и отступы не расходились по экранам.
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double input = 16;
  static const double card = 18;
  static const double sheet = 22;
  static const double nav = 24;
  static const double telegramBubble = 18;
  static const double telegramTile = 16;
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
  static const double floatingNavHeight = 50;
  static const double floatingNavSearchSize = 50;
  static const double telegramAvatar = 50;
  static const double telegramAvatarSmall = 42;
  static const double telegramUnreadBadge = 22;
}
