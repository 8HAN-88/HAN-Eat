import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'color_schemes.dart';

enum AppCardChrome {
  elevated,
  feed,
}

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
    this.chrome = AppCardChrome.elevated,
    this.sheen,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool showShadow;
  final AppCardChrome chrome;
  final bool? sheen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final showSheen = sheen ?? chrome == AppCardChrome.feed;

    final BoxDecoration decoration;
    if (chrome == AppCardChrome.feed) {
      decoration = AppCardDecorations.feed(
        theme,
        radius: radius,
        color: color,
        borderColor: borderColor,
        showShadow: showShadow,
      );
    } else if (showShadow) {
      final elevated = AppCardDecorations.elevated(
        theme,
        radius: radius,
        color: color,
      );
      decoration = borderColor == null
          ? elevated
          : elevated.copyWith(
              border: Border.all(color: borderColor!, width: 0.7),
            );
    } else {
      decoration = BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? scheme.outlineVariant,
          width: borderColor != null ? 0.7 : 0.5,
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
            if (showSheen)
              AppCardDecorations.topSheen(isDark: isDark, radius: radius),
          ],
        ),
      ),
    );
  }
}

/// Единый вид карточек на градиентном фоне (лента, меню, каналы).
class AppCardDecorations {
  AppCardDecorations._();

  static const double defaultRadius = AppRadius.card;
  static const double feedRadius = AppRadius.feedCard;

  static const Color hairlineLight = Color(0x38C4A574);
  static const Color hairlineDark = Color(0x48E8C9A0);

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
        color: isDark ? hairlineDark.withValues(alpha: 0.28) : hairlineLight,
        width: 0.6,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.05),
          blurRadius: isDark ? 18 : 14,
          offset: const Offset(0, 8),
          spreadRadius: -3,
        ),
      ],
    );
  }

  /// Framed feed / channel post: warm hairline, soft lift, brand glow.
  static BoxDecoration feed(
    ThemeData theme, {
    double radius = feedRadius,
    Color? color,
    Color? borderColor,
    bool showShadow = true,
  }) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? (isDark ? hairlineDark : hairlineLight),
        width: 0.7,
      ),
      boxShadow: showShadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.52 : 0.08),
                blurRadius: isDark ? 28 : 22,
                offset: const Offset(0, 12),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: AppColors.gradientEnd
                    .withValues(alpha: isDark ? 0.14 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -6,
              ),
            ]
          : const <BoxShadow>[],
    );
  }

  static Widget topSheen({
    required bool isDark,
    required double radius,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 1.15,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: isDark ? 0.18 : 0.58),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
