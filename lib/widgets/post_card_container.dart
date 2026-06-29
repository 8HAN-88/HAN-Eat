// Общий компонент для стилизации карточек постов
import 'package:flutter/material.dart';

import '../core/theme/app_card_decorations.dart';

/// Контейнер для карточки поста с красивым дизайном
/// Поддерживает кастомизацию фона и цветов
class PostCardContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final bool showShadow;

  const PostCardContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.margin,
    this.padding,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppElevatedCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      padding: padding,
      radius: borderRadius ?? 24,
      color: backgroundColor ??
          (dark
              ? scheme.surfaceContainer.withValues(alpha: 0.72)
              : scheme.surface),
      borderColor: borderColor ??
          (dark
              ? Colors.white.withValues(alpha: 0.06)
              : scheme.outlineVariant.withValues(alpha: 0.74)),
      showShadow: false,
      child: child,
    );
  }
}

/// Контейнер для карточки поста в канале с возможностью кастомизации фона
class ChannelPostCardContainer extends StatelessWidget {
  final Widget child;
  final Color? channelBackgroundColor;
  final Color? channelAccentColor;
  final double? borderRadius;
  final EdgeInsets? margin;
  final EdgeInsets? padding;

  const ChannelPostCardContainer({
    super.key,
    required this.child,
    this.channelBackgroundColor,
    this.channelAccentColor,
    this.borderRadius,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppElevatedCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      padding: padding,
      radius: borderRadius ?? 24,
      color: channelBackgroundColor ??
          (dark
              ? scheme.surfaceContainer.withValues(alpha: 0.72)
              : scheme.surface),
      borderColor: channelAccentColor?.withValues(alpha: 0.45) ??
          (dark
              ? Colors.white.withValues(alpha: 0.06)
              : scheme.outlineVariant.withValues(alpha: 0.74)),
      showShadow: false,
      child: child,
    );
  }
}
