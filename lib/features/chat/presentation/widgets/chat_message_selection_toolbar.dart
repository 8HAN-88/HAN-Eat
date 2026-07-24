import 'package:flutter/material.dart';

/// Нижняя панель действий при выборе нескольких сообщений.
class ChatMessageSelectionToolbar extends StatelessWidget {
  const ChatMessageSelectionToolbar({
    super.key,
    required this.enabled,
    required this.onDelete,
    required this.onCopy,
    required this.onShare,
    required this.onForward,
    this.onReply,
    this.canReply = false,
    this.onSaveToFavorites,
  });

  final bool enabled;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onForward;
  final VoidCallback? onReply;
  final bool canReply;
  final VoidCallback? onSaveToFavorites;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor =
        enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.35);
    final replyColor =
        canReply ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.35);
    final saveEnabled = enabled && onSaveToFavorites != null;
    final saveColor = saveEnabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.35);

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Ответить',
                onPressed: canReply ? onReply : null,
                icon: Icon(Icons.reply_rounded, color: replyColor),
              ),
              IconButton(
                tooltip: 'Удалить',
                onPressed: enabled ? onDelete : null,
                icon: Icon(Icons.delete_outline, color: iconColor),
              ),
              IconButton(
                tooltip: 'Копировать',
                onPressed: enabled ? onCopy : null,
                icon: Icon(Icons.copy_rounded, color: iconColor),
              ),
              if (onSaveToFavorites != null)
                IconButton(
                  tooltip: 'В избранное',
                  onPressed: saveEnabled ? onSaveToFavorites : null,
                  icon: Icon(Icons.bookmark_border_rounded, color: saveColor),
                ),
              IconButton(
                tooltip: 'Поделиться',
                onPressed: enabled ? onShare : null,
                icon: Icon(Icons.ios_share_rounded, color: iconColor),
              ),
              IconButton(
                tooltip: 'Переслать',
                onPressed: enabled ? onForward : null,
                icon: Icon(Icons.forward_rounded, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
