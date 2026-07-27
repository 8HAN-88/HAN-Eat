import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/haptics/app_haptics.dart';

/// Раскладка оверлея: реакции → сообщение → меню (как в Telegram).
class ChatMessageOverlayLayout {
  const ChatMessageOverlayLayout({
    required this.clusterTop,
    required this.clusterLeft,
    required this.clusterWidth,
    required this.messageWidth,
    required this.menuWidth,
    required this.reactionTop,
    required this.messageTop,
    required this.menuTop,
    required this.menuLeft,
  });

  final double clusterTop;
  final double clusterLeft;
  final double clusterWidth;
  final double messageWidth;
  final double menuWidth;
  final double reactionTop;
  final double messageTop;
  final double menuTop;
  final double menuLeft;

  static ChatMessageOverlayLayout compute({
    required Rect messageRect,
    required Size screenSize,
    required EdgeInsets padding,
    required int menuItemCount,
    required bool hasDivider,
    required int reactionCount,
    required bool isOutgoing,
    double menuWidth = 260,
    double reactionRowHeight = 48,
    double menuRowHeight = 46,
    double gap = 10,
    double bottomComposerReserve = 88,
  }) {
    const horizontalMargin = 12.0;
    final safeTop = padding.top + 8;
    final safeLeft = padding.left + horizontalMargin;
    final safeRight = screenSize.width - padding.right - horizontalMargin;
    final maxMenuBottom =
        screenSize.height - padding.bottom - bottomComposerReserve;

    final messageH = messageRect.height;
    final menuH = menuItemCount * menuRowHeight + (hasDivider ? 8 : 0);
    final clusterH = reactionRowHeight + gap + messageH + gap + menuH;

    const emojiSlot = 40.0;
    const expandSlot = 36.0;
    const reactionPad = 8.0;
    final reactionWidth =
        reactionPad * 2 + reactionCount * emojiSlot + expandSlot;

    final messageWidth = messageRect.width;
    final messageLeft =
        messageRect.left.clamp(safeLeft, safeRight - messageWidth);

    final clusterWidth = math.max(messageWidth, math.max(reactionWidth, menuWidth));
    final clusterLeft = isOutgoing
        ? (messageLeft + messageWidth - clusterWidth)
            .clamp(safeLeft, safeRight - clusterWidth)
        : messageLeft.clamp(safeLeft, safeRight - clusterWidth);

    // Кластер от исходной позиции пузыря.
    var clusterTop = messageRect.top - reactionRowHeight - gap;

    final menuBottomFromOriginal = clusterTop + clusterH;
    final messageInLowerZone =
        messageRect.center.dy >= screenSize.height * 0.52;
    final needsBottomAnchor =
        menuBottomFromOriginal > maxMenuBottom || messageInLowerZone;

    if (needsBottomAnchor) {
      clusterTop = maxMenuBottom - clusterH;
    }

    if (clusterTop < safeTop) {
      clusterTop = safeTop;
    }
    if (clusterTop + clusterH > maxMenuBottom) {
      clusterTop = math.max(safeTop, maxMenuBottom - clusterH);
    }

    final reactionTop = clusterTop;
    final messageTop = clusterTop + reactionRowHeight + gap;
    final menuTop = messageTop + messageH + gap;
    final menuLeft = isOutgoing
        ? clusterLeft + clusterWidth - menuWidth
        : clusterLeft;

    return ChatMessageOverlayLayout(
      clusterTop: clusterTop,
      clusterLeft: clusterLeft,
      clusterWidth: clusterWidth,
      messageWidth: messageWidth,
      menuWidth: menuWidth,
      reactionTop: reactionTop,
      messageTop: messageTop,
      menuTop: menuTop,
      menuLeft: menuLeft,
    );
  }
}

/// Меню действий над сообщением (реакции сверху, пункты снизу) — как в Telegram.
class ChatMessageActionOverlay extends StatefulWidget {
  const ChatMessageActionOverlay({
    super.key,
    required this.messageRect,
    required this.messagePreview,
    required this.quickReactions,
    required this.isOutgoing,
    required this.canEdit,
    required this.isPinned,
    required this.canDelete,
    required this.hasCopyableText,
    required this.onReaction,
    required this.onAction,
    required this.onExpandReactions,
    this.canShowReaders = false,
    this.canSaveToFavorites = false,
    this.canReplyPrivately = false,
    this.canCopyLink = false,
    this.canForward = true,
    this.canTranslate = false,
    this.canReport = false,
    this.bottomComposerReserve = 88,
  });

  final Rect messageRect;
  final Widget messagePreview;
  final List<String> quickReactions;
  final bool isOutgoing;
  final bool canEdit;
  final bool isPinned;
  final bool canDelete;
  final bool hasCopyableText;
  final bool canShowReaders;
  final bool canSaveToFavorites;
  final bool canReplyPrivately;
  final bool canCopyLink;
  final bool canForward;
  final bool canTranslate;
  final bool canReport;
  final ValueChanged<String> onReaction;
  final ValueChanged<String> onAction;
  final VoidCallback onExpandReactions;
  final double bottomComposerReserve;

  static Future<void> show({
    required BuildContext context,
    required Rect messageRect,
    required Widget messagePreview,
    required List<String> quickReactions,
    required bool isOutgoing,
    required bool canEdit,
    required bool isPinned,
    required bool canDelete,
    required bool hasCopyableText,
    required ValueChanged<String> onReaction,
    required ValueChanged<String> onAction,
    required VoidCallback onExpandReactions,
    bool canShowReaders = false,
    bool canSaveToFavorites = false,
    bool canReplyPrivately = false,
    bool canCopyLink = false,
    bool canForward = true,
    bool canTranslate = false,
    bool canReport = false,
    double bottomComposerReserve = 88,
  }) {
    AppHaptics.medium();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, animation, _, child) {
        final curve =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curve, child: child);
      },
      pageBuilder: (ctx, _, __) => ChatMessageActionOverlay(
        messageRect: messageRect,
        messagePreview: messagePreview,
        quickReactions: quickReactions,
        isOutgoing: isOutgoing,
        canEdit: canEdit,
        isPinned: isPinned,
        canDelete: canDelete,
        hasCopyableText: hasCopyableText,
        canShowReaders: canShowReaders,
        canSaveToFavorites: canSaveToFavorites,
        canReplyPrivately: canReplyPrivately,
        canCopyLink: canCopyLink,
        canForward: canForward,
        canTranslate: canTranslate,
        canReport: canReport,
        bottomComposerReserve: bottomComposerReserve,
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
  State<ChatMessageActionOverlay> createState() =>
      _ChatMessageActionOverlayState();
}

class _ChatMessageActionOverlayState extends State<ChatMessageActionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutCubic);
    _scaleCtrl.forward();
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    final menuBg = isDark
        ? const Color(0xFF2C2C2E).withValues(alpha: 0.96)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.98);
    final menuFg =
        isDark ? Colors.white.withValues(alpha: 0.95) : scheme.onSurface;
    final menuIcon = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : scheme.onSurfaceVariant;

    final menuItems = <_MenuItem>[
      _MenuItem(
        action: 'reply',
        icon: Icons.reply_rounded,
        label: 'Ответить',
      ),
      if (widget.canReplyPrivately)
        _MenuItem(
          action: 'reply_privately',
          icon: Icons.mark_chat_unread_outlined,
          label: 'Ответить лично',
        ),
      if (widget.hasCopyableText)
        _MenuItem(
          action: 'copy',
          icon: Icons.copy_rounded,
          label: 'Скопировать',
        ),
      if (widget.canEdit)
        _MenuItem(
          action: 'edit',
          icon: Icons.edit_outlined,
          label: 'Изменить',
        ),
      _MenuItem(
        action: 'pin',
        icon: widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: widget.isPinned ? 'Открепить' : 'Закрепить',
      ),
      if (widget.canForward)
        _MenuItem(
          action: 'forward',
          icon: Icons.forward_rounded,
          label: 'Переслать',
        ),
      if (widget.hasCopyableText && widget.canForward)
        _MenuItem(
          action: 'share',
          icon: Icons.ios_share_rounded,
          label: 'Поделиться',
        ),
      if (widget.canTranslate)
        _MenuItem(
          action: 'translate',
          icon: Icons.translate_rounded,
          label: 'Перевести',
        ),
      if (widget.canSaveToFavorites && widget.canForward)
        _MenuItem(
          action: 'save',
          icon: Icons.bookmark_border_rounded,
          label: 'В избранное',
        ),
      if (widget.canCopyLink)
        _MenuItem(
          action: 'copy_link',
          icon: Icons.link_rounded,
          label: 'Копировать ссылку',
        ),
      if (widget.canShowReaders)
        _MenuItem(
          action: 'readers',
          icon: Icons.done_all,
          label: 'Кто прочитал',
        ),
      if (widget.canReport)
        _MenuItem(
          action: 'report',
          icon: Icons.flag_outlined,
          label: 'Пожаловаться',
        ),
      if (widget.canDelete)
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
        showDividerBefore: widget.canDelete,
      ),
    ];

    const menuWidth = 260.0;
    const gap = 10.0;
    final layout = ChatMessageOverlayLayout.compute(
      messageRect: widget.messageRect,
      screenSize: size,
      padding: padding,
      menuItemCount: menuItems.length,
      hasDivider: widget.canDelete,
      reactionCount: widget.quickReactions.length,
      isOutgoing: widget.isOutgoing,
      menuWidth: menuWidth,
      bottomComposerReserve: widget.bottomComposerReserve,
    );

    final align = widget.isOutgoing
        ? Alignment.bottomRight
        : Alignment.bottomLeft;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.5)
                        : Colors.black.withValues(alpha: 0.32),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: layout.clusterLeft,
            top: layout.clusterTop,
            width: layout.clusterWidth,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(_scale),
              alignment: align,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: widget.isOutgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  _ReactionBar(
                    reactions: widget.quickReactions,
                    backgroundColor: menuBg,
                    onReaction: widget.onReaction,
                    onExpand: widget.onExpandReactions,
                  ),
                  const SizedBox(height: gap),
                  SizedBox(
                    width: layout.messageWidth,
                    child: widget.messagePreview,
                  ),
                  const SizedBox(height: gap),
                  SizedBox(
                    width: menuWidth,
                    child: _ActionMenu(
                      items: menuItems,
                      onAction: widget.onAction,
                      backgroundColor: menuBg,
                      foregroundColor: menuFg,
                      iconColor: menuIcon,
                      errorColor: scheme.error,
                    ),
                  ),
                ],
              ),
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
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < reactions.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onReaction(reactions[i]),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child:
                      Text(reactions[i], style: const TextStyle(fontSize: 26)),
                ),
              ),
            ],
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onExpand,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          color: items[i].destructive
                              ? errorColor
                              : foregroundColor,
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
