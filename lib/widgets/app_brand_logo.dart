import 'package:flutter/material.dart';

enum AppBrandLogoLayout {
  /// Квадратная иконка приложения.
  square,

  /// На экранах входа — компактный логотип по центру.
  horizontal,
}

/// Логотип HAN Eat (иконка приложения).
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 80,
    this.width = 72,
    this.layout = AppBrandLogoLayout.square,
    this.borderRadius = 16,
  });

  final double size;
  final double width;
  final AppBrandLogoLayout layout;
  final double borderRadius;

  static const _iconAsset = 'assets/app_icon_source.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHorizontal = layout == AppBrandLogoLayout.horizontal;
    final edge = isHorizontal ? width.clamp(64.0, 80.0) : size;
    final bg = theme.scaffoldBackgroundColor;

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: isHorizontal
              ? null
              : [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: EdgeInsets.all(isHorizontal ? edge * 0.08 : edge * 0.06),
            child: Image.asset(
              _iconAsset,
              width: edge,
              height: edge,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Icon(
                Icons.restaurant_menu,
                size: edge * 0.45,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
