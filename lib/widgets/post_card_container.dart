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
    return AppElevatedCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: padding,
      radius: borderRadius ?? 12,
      color: backgroundColor,
      borderColor: borderColor,
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
    return AppElevatedCard(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: padding,
      radius: borderRadius ?? 12,
      color: channelBackgroundColor,
      borderColor: channelAccentColor?.withValues(alpha: 0.45),
      showShadow: false,
      child: child,
    );
  }
}
