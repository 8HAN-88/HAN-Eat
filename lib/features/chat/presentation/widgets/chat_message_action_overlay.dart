import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/haptics/app_haptics.dart';

/// Меню действий над сообщением (реакции сверху, пункты снизу) — как в Telegram.
class ChatMessageActionOverlay extends StatelessWidget {
  const ChatMessageActionOverlay({
    super.key,
    required this.messageRect,
    required this.messagePreview,
    required this.quickReactions,
    required this.canEdit,
    required this.isPinned,
    required this.canDelete,
    required this.hasCopyableText,
    required this.onReaction,
    required this.onAction,
    required this.onExpandReactions,
  });

  final Rect messageRect;
  final Widget messagePreview;
  final List<String> quickReactions;
  final bool canEdit;
  final bool isPinned;
  final bool canDelete;
  final bool hasCopyableText;
  final ValueChanged<String> onReaction;
  final ValueChanged<String> onAction;
  final VoidCallback onExpandReactions;

  static Future<void> show({
    required BuildContext context,
    required Rect messageRect,
    required Widget messagePreview,
    required List<String> quickReactions,
    required bool canEdit,
    required bool isPinned,
    required bool canDelete,
    required bool hasCopyableText,
    required ValueChanged<String> onReaction,
    required ValueChanged<String> onAction,
    required VoidCallback onExpandReactions,
  }) {
    AppHaptics.medium();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) => ChatMessageActionOverlay(
        messageRect: messageRect,
        messagePreview: messagePreview,
        quickReactions: quickReactions,
        canEdit: canEdit,
        isPinned: isPinned,
        canDelete: canDelete,
        hasCopyableText: hasCopyableText,
        onReaction: (emoji) {
          Navigator.pop(ctx);
          onReaction(emoji);
        },
        onAction: (action) {
          Navigator.pop(ctx);
          onAction(action);
        },
        onExpandReactions: () {
          Navigator.pop(ctx);
          onExpandReactions();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    const reactionH = 48.0;
    const gap = 10.0;
    const menuWidth = 280.0;
    const rowH = 48.0;

    final menuBg = isDark
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.94)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.98);
    final menuFg = isDark ? Colors.white.withValues(alpha: 0.95) : scheme.onSurface;
    final menuIcon = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : scheme.onSurfaceVariant;

    final menuItems = <_MenuItem>[
      _MenuItem(
        action: 'reply',
        icon: Icons.reply_rounded,
        label: 'Ответить',
      ),
      if (hasCopyableText)
        _MenuItem(
          action: 'copy',
          icon: Icons.copy_rounded,
          label: 'Скопировать',
        ),
      if (canEdit)
        _MenuItem(
          action: 'edit',
          icon: Icons.edit_outlined,
          label: 'Изменить',
        ),
      _MenuItem(
        action: 'pin',
        icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: isPinned ? 'Открепить' : 'Закрепить',
      ),
      _MenuItem(
        action: 'forward',
        icon: Icons.forward_rounded,
        label: 'Переслать',
      ),
      if (canDelete)
        _MenuItem(
          action: 'delete',
          icon: Icons.delete_outline,
          label: 'Удалить',
          destructive: true,
        ),
      _MenuItem(
        action: 'select',
        icon: Icons.check_circle_outline,
        label: 'Выбрать',
        showDividerBefore: canDelete,
      ),
    ];

    final menuH = menuItems.length * rowH + (canDelete ? 8 : 0);
    final safeTop = padding.top + 8;
    final safeBottom = size.height - padding.bottom - 8;

    var menuTop = messageRect.bottom + gap;
    if (menuTop + menuH > safeBottom) {
      menuTop = messageRect.top - menuH - gap;
    }
    menuTop = menuTop.clamp(safeTop, math.max(safeTop, safeBottom - menuH));

    var reactionTop = messageRect.top - reactionH - gap;
    if (reactionTop < safeTop) {
      reactionTop = messageRect.bottom + gap;
      if (reactionTop + reactionH > menuTop - gap) {
        reactionTop = menuTop - reactionH - gap;
      }
    }
    reactionTop = reactionTop.clamp(safeTop, safeBottom - reactionH);

    final reactionMaxWidth = size.width - 16;
    final menuLeft =
        (messageRect.center.dx - menuWidth / 2).clamp(8.0, size.width - menuWidth - 8);
    final reactionLeft =
        (messageRect.center.dx - reactionMaxWidth / 2).clamp(8.0, size.width - 8);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.45)
                      : Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
          Positioned(
            left: messageRect.left,
            top: messageRect.top,
            width: messageRect.width,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: messagePreview,
            ),
          ),
          Positioned(
            left: reactionLeft,
            top: reactionTop,
            width: reactionMaxWidth,
            child: _ReactionBar(
              reactions: quickReactions,
              backgroundColor: menuBg,
              onReaction: onReaction,
              onExpand: onExpandReactions,
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            child: _ActionMenu(
              items: menuItems,
              onAction: onAction,
              backgroundColor: menuBg,
              foregroundColor: menuFg,
              iconColor: menuIcon,
              errorColor: scheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactions,
    required this.backgroundColor,
    required this.onReaction,
    required this.onExpand,
  });

  final List<String> reactions;
  final Color backgroundColor;
  final ValueChanged<String> onReaction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: reactions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 2),
                itemBuilder: (context, index) {
                  final emoji = reactions[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onReaction(emoji),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                },
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.action,
    required this.icon,
    required this.label,
    this.destructive = false,
    this.showDividerBefore = false,
  });

  final String action;
  final IconData icon;
  final String label;
  final bool destructive;
  final bool showDividerBefore;
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.items,
    required this.onAction,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.iconColor,
    required this.errorColor,
  });

  final List<_MenuItem> items;
  final ValueChanged<String> onAction;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (items[i].showDividerBefore)
              Divider(
                height: 1,
                color: foregroundColor.withValues(alpha: 0.12),
              ),
            InkWell(
              onTap: () => onAction(items[i].action),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      items[i].icon,
                      size: 22,
                      color: items[i].destructive ? errorColor : iconColor,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 16,
                          color: items[i].destructive ? errorColor : foregroundColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
