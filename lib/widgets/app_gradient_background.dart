import 'package:flutter/material.dart';

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
        if (isDark) const _DarkBackground() else const _LightBackground(),
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF0E7),
            Color(0xFFFFFBF7),
            Color(0xFFF3F6FF),
          ],
          stops: [0.0, 0.48, 1.0],
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF101827),
            Color(0xFF11151F),
            Color(0xFF070A10),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
