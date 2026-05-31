import 'package:flutter/material.dart';

/// Логотип приложения (тот же, что на иконке на домашнем экране).
class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.size = 80,
    this.borderRadius = 20,
  });

  final double size;
  final double borderRadius;

  static const _assetPath = 'assets/app_icon_source.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        _assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.restaurant_menu,
          size: size,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
