import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'highlighted_text.dart';

class TelegramSectionHeader extends StatelessWidget {
  const TelegramSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 8),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class TelegramGroupedSurface extends StatelessWidget {
  const TelegramGroupedSurface({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
      child: child,
    );
  }
}

/// Animated «…» for typing / recording subtitles (Telegram-style).
class TelegramTypingDots extends StatefulWidget {
  const TelegramTypingDots({
    super.key,
    this.color,
    this.size = 3.5,
  });

  final Color? color;
  final double size;

  @override
  State<TelegramTypingDots> createState() => _TelegramTypingDotsState();
}

class _TelegramTypingDotsState extends State<TelegramTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value + i * 0.18) % 1.0;
            final bounce = math.sin(t * math.pi).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2.5),
              child: Transform.translate(
                offset: Offset(0, -2.2 * bounce),
                child: Opacity(
                  opacity: 0.35 + 0.65 * bounce,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class TelegramUnreadBadge extends StatelessWidget {
  const TelegramUnreadBadge({
    super.key,
    required this.count,
    this.muted = false,
    this.hasMention = false,
    this.hasReaction = false,
  });

  final int count;
  final bool muted;
  /// Telegram-style `@` badge when there are unread @mentions.
  final bool hasMention;
  /// Telegram-style ❤ badge when there are unread reactions on my messages.
  final bool hasReaction;

  @override
  Widget build(BuildContext context) {
    if (count <= 0 && !hasMention && !hasReaction) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final label = hasMention
        ? '@'
        : (hasReaction ? '❤' : (count > 99 ? '99+' : '$count'));
    final symbolic = hasMention || hasReaction;
    return Container(
      constraints: const BoxConstraints(
        minWidth: AppSizes.telegramUnreadBadge,
        minHeight: AppSizes.telegramUnreadBadge,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? scheme.outline : scheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: muted ? scheme.surface : scheme.onPrimary,
          fontSize: symbolic ? 13 : 11,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class TelegramActionRow extends StatelessWidget {
  const TelegramActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: (iconColor ?? scheme.primary).withValues(alpha: 0.14),
        child: Icon(icon, size: 20, color: iconColor ?? scheme.primary),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}

class TelegramPill extends StatelessWidget {
  const TelegramPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NeoGlassCard extends StatelessWidget {
  const NeoGlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    this.padding = EdgeInsets.zero,
    this.radius = 24,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: dark
            ? scheme.surfaceContainer.withValues(alpha: 0.72)
            : scheme.surface.withValues(alpha: 0.92),
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.06)
              : scheme.outlineVariant.withValues(alpha: 0.74),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class NeoCircleAction extends StatelessWidget {
  const NeoCircleAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.18)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.72);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: selected ? scheme.primary : scheme.onSurface,
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.outlineVariant.withValues(alpha: 0.45),
          width: 0.7,
        ),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class NeoFilterChip extends StatelessWidget {
  const NeoFilterChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.13)
        : scheme.surfaceContainer.withValues(alpha: 0.7);
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.18)
                  : scheme.outlineVariant.withValues(alpha: 0.38),
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NeoUnderlineTabs extends StatelessWidget {
  const NeoUnderlineTabs({
    super.key,
    required this.controller,
    required this.tabs,
    this.height = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
  });

  final TabController controller;
  final List<Widget> tabs;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: padding,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
          width: 0.7,
        ),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.5),
          borderRadius: BorderRadius.circular(999),
          insets: const EdgeInsets.only(bottom: 7),
        ),
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
        unselectedLabelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
        tabs: tabs,
      ),
    );
  }
}

class TelegramActionSheetAction {
  const TelegramActionSheetAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final Widget? trailing;
}

Future<T?> showTelegramActionSheet<T>({
  required BuildContext context,
  required String title,
  required List<TelegramActionSheetAction> actions,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (sheetContext) => TelegramActionSheet(
      title: title,
      actions: actions,
    ),
  );
}

class TelegramActionSheet extends StatelessWidget {
  const TelegramActionSheet({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final List<TelegramActionSheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark
        ? const Color(0xFF1C1D22).withValues(alpha: 0.92)
        : scheme.surface.withValues(alpha: 0.94);
    final border = dark
        ? Colors.white.withValues(alpha: 0.05)
        : scheme.outlineVariant.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: border, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.38 : 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    HighlightedText(
                      text: title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ) ??
                          const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 18),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.025)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            _TelegramActionSheetRow(action: actions[i]),
                            if (i != actions.length - 1)
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 54,
                                color: scheme.outlineVariant
                                    .withValues(alpha: dark ? 0.16 : 0.7),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TelegramActionSheetRow extends StatelessWidget {
  const _TelegramActionSheetRow({required this.action});

  final TelegramActionSheetAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = action.destructive ? scheme.error : scheme.onSurface;
    final iconFg = action.destructive ? scheme.error : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.pop(context);
          action.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          child: Row(
            children: [
              Icon(action.icon, color: iconFg, size: 25),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HighlightedText(
                      text: action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w500,
                          ) ??
                          TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                    ),
                    if (action.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: HighlightedText(
                          text: action.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ) ??
                              TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              action.trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                    size: 24,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
