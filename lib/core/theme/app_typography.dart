import 'package:flutter/material.dart';

/// Единая типографика (Manrope в assets, без загрузки из сети).
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Manrope';

  static String? get fontFamilyNullable => fontFamily;

  static TextTheme textTheme(ColorScheme scheme, Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true).textTheme
        : ThemeData.dark(useMaterial3: true).textTheme;

    final manrope = base.apply(
      fontFamily: fontFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return manrope.copyWith(
      displayLarge: manrope.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      displayMedium: manrope.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: manrope.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleLarge: manrope.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: manrope.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: manrope.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: manrope.bodyLarge?.copyWith(
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: manrope.bodyMedium?.copyWith(
        height: 1.4,
      ),
      bodySmall: manrope.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.35,
      ),
      labelLarge: manrope.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: manrope.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      labelSmall: manrope.labelSmall?.copyWith(
        letterSpacing: 0.2,
      ),
    );
  }
}
