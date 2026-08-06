import 'package:flutter/material.dart';

class AppColors {
  // Telegram-like structure with HanWe brand orange as the main accent.
  static const primary = Color(0xFFFF6B35);
  static const primaryDark = Color(0xFFE85A2B);
  static const primaryLight = Color(0xFFFF9D7A);
  static const foodOrange = primary;
  // Keep the historical name, but map it to brand orange — not Telegram blue.
  static const telegramBlue = primary;
  static const telegramBlueDark = primaryDark;
  static const telegramOutgoingLight = Color(0xFFEFFEDD);
  static const telegramOutgoingDark = Color(0xFF6A3423);
  static const telegramChatBgLight = Color(0xFFE7EBF0);
  static const telegramChatBgDark = Color(0xFF0E1621);

  static const secondary = primary;
  static const secondaryDark = primaryDark;

  /// Telegram light lists are mostly white, with pale gray behind grouped areas.
  static const backgroundLight = Color(0xFFF4F4F5);

  /// Neo dark base used by the X-inspired mobile screens.
  static const backgroundDark = Color(0xFF05080E);

  /// Карточки и «поднятые» блоки в светлой теме.
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF10151D);

  /// Приглушённые блоки (чипы, подложки) — нейтральный серый.
  static const surfaceVariant = Color(0xFFF1F3F5);

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
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFFFEEE7),
    onPrimaryContainer: const Color(0xFF6A321E),
    secondary: AppColors.foodOrange,
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
    surfaceContainerLow: const Color(0xFFFFFFFF),
    surfaceContainer: const Color(0xFFF1F3F5),
    surfaceContainerHigh: const Color(0xFFE6EAEE),
    surfaceContainerHighest: const Color(0xFFD8DEE5),
    onSurface: const Color(0xFF111111),
    onSurfaceVariant: const Color(0xFF707579),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFF2A2D35),
    onInverseSurface: const Color(0xFFF1F3F6),
    inversePrimary: AppColors.primaryLight,
    outline: const Color(0xFFDADCE0),
    outlineVariant: const Color(0xFFE6E7EA),
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
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFF5A2C20),
    onPrimaryContainer: const Color(0xFFFFE8E0),
    secondary: AppColors.foodOrange,
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
    surfaceContainerLow: const Color(0xFF0B1018),
    surfaceContainer: const Color(0xFF111821),
    surfaceContainerHigh: const Color(0xFF171F2B),
    surfaceContainerHighest: const Color(0xFF202A37),
    onSurface: const Color(0xFFEFF3F7),
    onSurfaceVariant: const Color(0xFF9AA8B5),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFFE8EAEF),
    onInverseSurface: const Color(0xFF1A1D22),
    inversePrimary: AppColors.primaryDark,
    outline: const Color(0xFF334050),
    outlineVariant: const Color(0xFF1C2633),
    shadow: Colors.black,
    scrim: Colors.black.withValues(alpha: 0.6),
  );
}
