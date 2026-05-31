import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Единая типографика (Manrope: Latin + Cyrillic + extended Latin) для всех языков.
class AppTypography {
  AppTypography._();

  /// Один шрифт для ru/en/es/de/fr — DM Sans не содержит кириллицу, из‑за этого
  /// русский текст рендерился системным шрифтом.
  static String? get fontFamily => GoogleFonts.manrope().fontFamily;

  static TextTheme textTheme(ColorScheme scheme, Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true).textTheme
        : ThemeData.dark(useMaterial3: true).textTheme;

    final manrope = GoogleFonts.manropeTextTheme(base).apply(
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
