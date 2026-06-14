import 'package:flutter/material.dart';

enum AppBrandLogoLayout {
  /// Квадратная иконка приложения.
  square,

  /// На экранах входа — только буквы HAN без фона и рамок.
  horizontal,
}

/// Логотип HAN Eat.
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 80,
    this.width = 140,
    this.layout = AppBrandLogoLayout.square,
    this.borderRadius = 16,
  });

  final double size;
  final double width;
  final AppBrandLogoLayout layout;
  final double borderRadius;

  static const _iconAsset = 'assets/app_icon_source.png';
  static const _lettersAsset = 'assets/brand_logo.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHorizontal = layout == AppBrandLogoLayout.horizontal;

    if (isHorizontal) {
      final logoWidth = width.clamp(120.0, 220.0);
      return Image.asset(
        _lettersAsset,
        width: logoWidth,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Icon(
          Icons.restaurant_menu,
          size: logoWidth * 0.35,
          color: theme.colorScheme.primary,
        ),
      );
    }

    final edge = size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        _iconAsset,
        width: edge,
        height: edge,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Icon(
          Icons.restaurant_menu,
          size: edge * 0.45,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
