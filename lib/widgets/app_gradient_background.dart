import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Фон для основных вкладок.
///
/// Светлая тема — мягкий брендовый canvas; тёмная — глубокий вертикальный градиент.
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
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFBF7),
            Color(0xFFFFF9F5),
            Color(0xFFF8F6F3),
          ],
          stops: [0.0, 0.35, 1.0],
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
            Color(0xFF0B0E14),
            Color(0xFF10151D),
            Color(0xFF0C0F16),
          ],
          stops: [0.0, 0.42, 1.0],
        ),
      ),
    );
  }
}
