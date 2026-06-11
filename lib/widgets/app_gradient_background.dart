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
          const ColoredBox(color: AppColors.backgroundLight),
        child,
      ],
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
