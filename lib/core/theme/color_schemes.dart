import 'package:flutter/material.dart';

class AppColors {
  // HAN Eat action accent. Telegram blue is used for navigation, links and unread states.
  static const primary = Color(0xFFFF6B35);
  static const primaryDark = Color(0xFFE85A2B);
  static const primaryLight = Color(0xFFFF9D7A);
  static const telegramBlue = Color(0xFF2AABEE);
  static const telegramBlueDark = Color(0xFF229ED9);

  static const secondary = telegramBlue;
  static const secondaryDark = telegramBlueDark;

  /// База светлой темы — ровный нейтральный белый без тёплого градиента.
  static const backgroundLight = Color(0xFFF4F6F8);

  /// Единый фон тёмной темы: холодный графит.
  static const backgroundDark = Color(0xFF0F141A);

  /// Карточки и «поднятые» блоки в светлой теме.
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF18222D);

  /// Приглушённые блоки (чипы, подложки) — нейтральный серый.
  static const surfaceVariant = Color(0xFFEFF3F7);

  // Акцентные цвета
  static const success = Color(0xFF4CAF50); // Зелёный (свежесть, здоровье)
  static const warning = Color(0xFFFFC107); // Тёплый жёлтый
  static const danger = Color(0xFFE53935); // Красный

  // Градиенты для декоративных элементов
  static const gradientStart = Color(0xFFFF6B35);
  static const gradientEnd = Color(0xFFFFB347);
}

ColorScheme buildLightColorScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  );

  return base.copyWith(
    primary: AppColors.telegramBlue,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE7F5FE),
    onPrimaryContainer: const Color(0xFF0B4F70),
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFEEE7),
    onSecondaryContainer: const Color(0xFF6A321E),
    tertiary: const Color(0xFF66BB6A),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFE8F5E9),
    onTertiaryContainer: const Color(0xFF1F4D2A),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: const Color(0xFFFFE8E8),
    onErrorContainer: const Color(0xFF6B1F1F),
    surface: AppColors.surface,
    surfaceContainerLowest: AppColors.backgroundLight,
    surfaceContainerLow: const Color(0xFFF8FAFC),
    surfaceContainer: const Color(0xFFEFF3F7),
    surfaceContainerHigh: const Color(0xFFE6EDF3),
    surfaceContainerHighest: const Color(0xFFDDE6EE),
    onSurface: const Color(0xFF111820),
    onSurfaceVariant: const Color(0xFF637282),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFF2A2D35),
    onInverseSurface: const Color(0xFFF1F3F6),
    inversePrimary: AppColors.primaryLight,
    outline: const Color(0xFFD7E0E8),
    outlineVariant: const Color(0xFFE5EDF4),
    shadow: Colors.black.withValues(alpha: 0.1),
    scrim: Colors.black.withValues(alpha: 0.4),
  );
}

ColorScheme buildDarkColorScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  );

  return base.copyWith(
    primary: AppColors.telegramBlue,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF143D54),
    onPrimaryContainer: const Color(0xFFDDF4FF),
    secondary: AppColors.primary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF5A2C20),
    onSecondaryContainer: const Color(0xFFFFE8E0),
    tertiary: const Color(0xFF81C784),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFF3A5A3F),
    onTertiaryContainer: const Color(0xFFE8F5E9),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: const Color(0xFF8B2D2D),
    onErrorContainer: const Color(0xFFFFE8E8),
    surface: AppColors.surfaceDark,
    surfaceContainerLowest: AppColors.backgroundDark,
    surfaceContainerLow: const Color(0xFF131A22),
    surfaceContainer: const Color(0xFF18222D),
    surfaceContainerHigh: const Color(0xFF202C38),
    surfaceContainerHighest: const Color(0xFF293746),
    onSurface: const Color(0xFFEFF5FA),
    onSurfaceVariant: const Color(0xFFA9B7C5),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFFE8EAEF),
    onInverseSurface: const Color(0xFF1A1D22),
    inversePrimary: AppColors.primaryDark,
    outline: const Color(0xFF405162),
    outlineVariant: const Color(0xFF2B3A48),
    shadow: Colors.black,
    scrim: Colors.black.withValues(alpha: 0.6),
  );
}
