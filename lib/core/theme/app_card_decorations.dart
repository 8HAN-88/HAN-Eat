import 'package:flutter/material.dart';

/// Карточка с единым фоном рамки (лента, меню, каналы).
class AppElevatedCard extends StatelessWidget {
  const AppElevatedCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.radius = AppCardDecorations.defaultRadius,
    this.color,
    this.borderColor,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    BoxDecoration decoration;
    if (showShadow) {
      decoration = AppCardDecorations.elevated(
        theme,
        radius: radius,
        color: color,
      );
    } else {
      decoration = BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant,
          width: borderColor != null ? 1 : 0.5,
        ),
      );
    }

    if (borderColor != null && showShadow) {
      decoration = BoxDecoration(
        color: decoration.color,
        borderRadius: decoration.borderRadius,
        border: Border.all(color: borderColor!, width: 1),
        boxShadow: decoration.boxShadow,
      );
    }

    return Container(
      margin: margin,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}

/// Единый вид карточек на градиентном фоне (лента, меню, каналы).
class AppCardDecorations {
  AppCardDecorations._();

  static const double defaultRadius = 22;

  static BoxDecoration elevated(
    ThemeData theme, {
    double radius = defaultRadius,
    Color? color,
  }) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.65 : 1),
        width: 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.35)
              : scheme.shadow.withValues(alpha: 0.1),
          blurRadius: isDark ? 8 : 12,
          offset: Offset(0, isDark ? 2 : 4),
        ),
      ],
    );
  }
}
