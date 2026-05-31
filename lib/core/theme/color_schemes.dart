import 'package:flutter/material.dart';

class AppColors {
  // Акцент (оранжевый) — для кнопок и ссылок; фон приложения — нейтральный, без «коричневого».
  static const primary = Color(0xFFFF6B35);
  static const primaryDark = Color(0xFFE85A2B);
  static const primaryLight = Color(0xFFFF9D7A);

  static const secondary = Color(0xFFFFB347);
  static const secondaryDark = Color(0xFFFF9A1F);

  /// Единый фон светлой темы: холодный серо-синий (не бежевый / не коричневатый).
  static const backgroundLight = Color(0xFFF3F5F8);
  /// Единый фон тёмной темы: холодный графит.
  static const backgroundDark = Color(0xFF0E1116);

  /// Карточки и «поднятые» блоки в светлой теме.
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF171B22);
  /// Приглушённые блоки (чипы, подложки) — нейтральный серый.
  static const surfaceVariant = Color(0xFFE9ECF1);
  
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
    primaryContainer: const Color(0xFFFFE8E0),
    onPrimaryContainer: const Color(0xFF6B2F1A),
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFF4E0),
    onSecondaryContainer: const Color(0xFF6B4A1F),
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
    surfaceContainerLow: const Color(0xFFF0F2F6),
    surfaceContainer: const Color(0xFFEBEEF3),
    surfaceContainerHigh: const Color(0xFFE5E9EF),
    surfaceContainerHighest: AppColors.surfaceVariant,
    onSurface: const Color(0xFF16181D),
    onSurfaceVariant: const Color(0xFF5E6670),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFF2A2D35),
    onInverseSurface: const Color(0xFFF1F3F6),
    inversePrimary: AppColors.primaryLight,
    outline: const Color(0xFFD0D6DE),
    outlineVariant: const Color(0xFFE4E8EF),
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
    primaryContainer: const Color(0xFF8B3D2B),
    onPrimaryContainer: const Color(0xFFFFE8E0),
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF8B6A3D),
    onSecondaryContainer: const Color(0xFFFFF4E0),
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
    surfaceContainerLow: const Color(0xFF141920),
    surfaceContainer: const Color(0xFF1A2129),
    surfaceContainerHigh: const Color(0xFF212830),
    surfaceContainerHighest: const Color(0xFF2A323D),
    onSurface: const Color(0xFFECEFF4),
    onSurfaceVariant: const Color(0xFFB4BAC6),
    surfaceTint: Colors.transparent,
    inverseSurface: const Color(0xFFE8EAEF),
    onInverseSurface: const Color(0xFF1A1D22),
    inversePrimary: AppColors.primaryDark,
    outline: const Color(0xFF4A5568),
    outlineVariant: const Color(0xFF343C48),
    shadow: Colors.black,
    scrim: Colors.black.withValues(alpha: 0.6),
  );
}
