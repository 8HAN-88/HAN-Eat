import 'package:flutter/material.dart';

import 'app_typography.dart';
import 'color_schemes.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = buildLightColorScheme();
    final textTheme = AppTypography.textTheme(scheme, Brightness.light);
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      splashColor: scheme.primary.withValues(alpha: 0.12),
      highlightColor: scheme.primary.withValues(alpha: 0.06),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundLight,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.primary.withValues(alpha: 0.08),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.5,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primaryContainer.withValues(alpha: 0.6),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary.withValues(alpha: 0.16),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.backgroundLight,
        elevation: 3,
        shadowColor: scheme.primary.withValues(alpha: 0.14),
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = buildDarkColorScheme();
    final textTheme = AppTypography.textTheme(scheme, Brightness.dark);
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      splashColor: scheme.primary.withValues(alpha: 0.18),
      highlightColor: scheme.primary.withValues(alpha: 0.08),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.5,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primaryContainer.withValues(alpha: 0.45),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary.withValues(alpha: 0.22),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.backgroundDark,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        indicatorColor: scheme.primary.withValues(alpha: 0.25),
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: scheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 0.8,
          ),
        ),
        elevation: 10,
        insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      ),
    );
  }
}
