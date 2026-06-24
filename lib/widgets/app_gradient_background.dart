import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Фон для основных вкладок.
///
/// Светлая тема — ровный нейтральный canvas; тёмная — мягкий вертикальный градиент.
class AppGradientBackground extends StatelessWidget {
  const AppGradientBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isDark)
          const _DarkBackground()
        else
          const _LightBackground(),
        child,
      ],
    );
  }
}

class _LightBackground extends StatelessWidget {
  const _LightBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.04),
            AppColors.backgroundLight,
            const Color(0xFFEEF1F6),
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
    );
  }
}

class _DarkBackground extends StatelessWidget {
  const _DarkBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F1319),
            Color(0xFF141A22),
            Color(0xFF0D1015),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
    );
  }
}
