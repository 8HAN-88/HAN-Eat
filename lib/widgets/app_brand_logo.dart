import 'dart:ui';

import 'package:flutter/material.dart';

enum AppBrandLogoLayout {
  /// Квадрат — иконка, миниатюры.
  square,

  /// Символ букв целиком (экран входа).
  horizontal,
}

/// Логотип HAN Eat.
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 80,
    this.width = 200,
    this.layout = AppBrandLogoLayout.square,
    this.borderRadius = 20,
  });

  final double size;
  final double width;
  final AppBrandLogoLayout layout;
  final double borderRadius;

  static const _squareAsset = 'assets/app_icon_source.png';
  static const _symbolAsset = 'assets/brand_logo.png';

  /// Соотношение сторон вырезанного символа (758×565).
  static const _symbolAspect = 758 / 565;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHorizontal = layout == AppBrandLogoLayout.horizontal;
    final symbolHeight = width / _symbolAspect;

    final symbol = Image.asset(
      _symbolAsset,
      fit: BoxFit.contain,
      width: isHorizontal ? width : size,
      height: isHorizontal ? symbolHeight : size,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        Icons.restaurant_menu,
        size: isHorizontal ? width * 0.4 : size,
        color: theme.colorScheme.primary,
      ),
    );

    if (!isHorizontal) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          _squareAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.restaurant_menu,
            size: size,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    // Только символ на прозрачном фоне + мягкое свечение за буквами.
    return Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Opacity(
              opacity: 0.35,
              child: symbol,
            ),
          ),
          symbol,
        ],
      ),
    );
  }
}
