import 'package:flutter/material.dart';

class AppColors {
  // Современная палитра для приложения о еде - тёплые, аппетитные цвета
  static const primary = Color(0xFFFF6B35); // Тёплый оранжево-красный (аппетитный)
  static const primaryDark = Color(0xFFE85A2B);
  static const primaryLight = Color(0xFFFF9D7A);
  
  // Вторичный цвет - тёплый жёлто-оранжевый
  static const secondary = Color(0xFFFFB347); // Золотистый
  static const secondaryDark = Color(0xFFFF9A1F);
  
  // Фоны - мягкие, нейтральные оттенки
  static const backgroundLight = Color(0xFFFAFAF8); // Тёплый бежевый
  static const backgroundDark = Color(0xFF1A1A18); // Тёмный нейтральный
  
  // Поверхности
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF252522);
  static const surfaceVariant = Color(0xFFF5F5F3); // Очень светлый бежевый
  
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
    primaryContainer: const Color(0xFFFFE8E0), // Очень светлый оранжевый
    onPrimaryContainer: const Color(0xFF6B2F1A),
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFF4E0), // Светлый жёлтый
    onSecondaryContainer: const Color(0xFF6B4A1F),
    tertiary: const Color(0xFF66BB6A), // Зелёный акцент (свежесть)
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFE8F5E9),
    onTertiaryContainer: const Color(0xFF1F4D2A),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: const Color(0xFFFFE8E8),
    onErrorContainer: const Color(0xFF6B1F1F),
    surface: AppColors.surface,
    surfaceVariant: AppColors.surfaceVariant,
    onSurface: const Color(0xFF2A1F1F),
    onSurfaceVariant: const Color(0xFF5A4A4A),
    surfaceTint: AppColors.primary,
    inverseSurface: const Color(0xFF2A1F1F),
    onInverseSurface: const Color(0xFFF5F5F3),
    inversePrimary: AppColors.primaryLight,
    outline: const Color(0xFFE0D5D0), // Мягкая граница
    outlineVariant: const Color(0xFFF0E8E3), // Очень мягкая граница
    shadow: Colors.black.withOpacity(0.1),
    scrim: Colors.black.withOpacity(0.4),
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
    primaryContainer: const Color(0xFF8B3D2B), // Тёмный оранжевый
    onPrimaryContainer: const Color(0xFFFFE8E0),
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF8B6A3D), // Тёмный жёлтый
    onSecondaryContainer: const Color(0xFFFFF4E0),
    tertiary: const Color(0xFF81C784), // Светлый зелёный
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFF3A5A3F),
    onTertiaryContainer: const Color(0xFFE8F5E9),
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: const Color(0xFF8B2D2D),
    onErrorContainer: const Color(0xFFFFE8E8),
    surface: AppColors.surfaceDark,
    surfaceVariant: const Color(0xFF3A3440),
    onSurface: const Color(0xFFF5F5F3), // Светлый бежевый
    onSurfaceVariant: const Color(0xFFC8C0B8),
    surfaceTint: AppColors.primary,
    inverseSurface: const Color(0xFFF5E8E3),
    onInverseSurface: const Color(0xFF2A1F1F),
    inversePrimary: AppColors.primaryDark,
    outline: const Color(0xFF6B5A55), // Мягкая граница
    outlineVariant: const Color(0xFF4A3A35), // Очень мягкая граница
    shadow: Colors.black,
    scrim: Colors.black.withOpacity(0.6),
  );
}
