import 'package:flutter/material.dart';

import '../core/theme/color_schemes.dart';

/// Аватар с мягким градиентным кольцом (профиль, шапки).
class AppAvatarRing extends StatelessWidget {
  const AppAvatarRing({
    super.key,
    required this.size,
    required this.child,
    this.ringWidth = 3,
  });

  final double size;
  final Widget child;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size + ringWidth * 2,
      height: size + ringWidth * 2,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.primary.withValues(alpha: 0.85),
                  AppColors.secondary.withValues(alpha: 0.65),
                ]
              : [
                  AppColors.primary,
                  AppColors.secondary,
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: child,
        ),
      ),
    );
  }
}
