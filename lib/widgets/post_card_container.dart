// Общий компонент для стилизации карточек постов
import 'package:flutter/material.dart';

/// Контейнер для карточки поста с красивым дизайном
/// Поддерживает кастомизацию фона и цветов
class PostCardContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final List<BoxShadow>? boxShadow;
  final bool showShadow;
  
  const PostCardContainer({
    Key? key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.margin,
    this.padding,
    this.boxShadow,
    this.showShadow = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? (isDark ? Colors.grey[900] : Colors.white),
        borderRadius: BorderRadius.circular(borderRadius ?? 16),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1)
            : null,
        boxShadow: showShadow
            ? (boxShadow ?? [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.5)
                      : Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                  spreadRadius: 0,
                ),
              ])
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius ?? 16),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
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
    Key? key,
    required this.child,
    this.channelBackgroundColor,
    this.channelAccentColor,
    this.borderRadius,
    this.margin,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Используем цвет канала, если указан, иначе стандартный
    final bgColor = channelBackgroundColor ?? 
        (isDark ? Colors.grey[900] : Colors.white);
    
    // Если есть accent color, добавляем тонкую границу
    final borderColor = channelAccentColor != null
        ? channelAccentColor!.withOpacity(0.3)
        : null;
    
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius ?? 16),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.5)
                : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius ?? 16),
        child: Container(
          decoration: channelAccentColor != null
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      channelAccentColor!.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                )
              : null,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}

