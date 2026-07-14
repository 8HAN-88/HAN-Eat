import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/haptics/app_haptics.dart';

/// Свайп влево — кнопки действий (не мгновенный архив).
class ChatInboxSlidable extends StatelessWidget {
  const ChatInboxSlidable({
    super.key,
    required this.chatId,
    required this.muted,
    required this.child,
    required this.onArchive,
    required this.onToggleMute,
    required this.onDelete,
    this.enabled = true,
  });

  final int chatId;
  final bool muted;
  final Widget child;
  final VoidCallback onArchive;
  final VoidCallback onToggleMute;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final scheme = Theme.of(context).colorScheme;
    return Slidable(
      key: ValueKey('chat_slidable_$chatId'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.56,
        children: [
          SlidableAction(
            onPressed: (_) => _run(context, onArchive),
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            icon: Icons.archive_outlined,
            label: 'Архив',
          ),
          SlidableAction(
            onPressed: (_) => _run(context, onToggleMute),
            backgroundColor: scheme.tertiaryContainer,
            foregroundColor: scheme.onTertiaryContainer,
            icon: muted
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            label: muted ? 'Вкл' : 'Тихо',
          ),
          SlidableAction(
            onPressed: (_) => _run(context, onDelete),
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            icon: Icons.delete_outline,
            label: 'Удалить',
          ),
        ],
      ),
      child: child,
    );
  }

  void _run(BuildContext context, VoidCallback action) {
    AppHaptics.light();
    Slidable.of(context)?.close();
    action();
  }
}

class ChannelInboxSlidable extends StatelessWidget {
  const ChannelInboxSlidable({
    super.key,
    required this.channelId,
    required this.child,
    required this.onArchive,
    required this.onLeave,
  });

  final int channelId;
  final Widget child;
  final VoidCallback onArchive;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Slidable(
      key: ValueKey('channel_slidable_$channelId'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.38,
        children: [
          SlidableAction(
            onPressed: (_) => _run(context, onArchive),
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            icon: Icons.archive_outlined,
            label: 'Архив',
          ),
          SlidableAction(
            onPressed: (_) => _run(context, onLeave),
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
            icon: Icons.logout_rounded,
            label: 'Выйти',
          ),
        ],
      ),
      child: child,
    );
  }

  void _run(BuildContext context, VoidCallback action) {
    AppHaptics.light();
    Slidable.of(context)?.close();
    action();
  }
}
