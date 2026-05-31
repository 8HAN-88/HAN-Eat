import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Лёгкий градиент фона для основных вкладок (без тяжёлых эффектов).
class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.backgroundDark,
                  scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                  AppColors.backgroundDark,
                ]
              : [
                  AppColors.backgroundLight,
                  scheme.primaryContainer.withValues(alpha: 0.22),
                  AppColors.surfaceVariant.withValues(alpha: 0.9),
                ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: child,
    );
  }
}
