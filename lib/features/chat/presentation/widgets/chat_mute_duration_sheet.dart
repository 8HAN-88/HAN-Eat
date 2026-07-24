import 'package:flutter/material.dart';

/// Result of mute duration picker.
/// - `unmute`: turn notifications back on
/// - `duration == null`: mute forever
/// - otherwise mute until now + duration
class ChatMuteChoice {
  const ChatMuteChoice._({required this.unmute, this.duration});

  const ChatMuteChoice.unmute() : this._(unmute: true);
  const ChatMuteChoice.forever() : this._(unmute: false);
  const ChatMuteChoice.forDuration(Duration duration)
      : this._(unmute: false, duration: duration);

  final bool unmute;
  final Duration? duration;
}

Future<ChatMuteChoice?> showChatMuteDurationSheet(
  BuildContext context, {
  required bool currentlyMuted,
}) {
  return showModalBottomSheet<ChatMuteChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                currentlyMuted ? 'Уведомления' : 'Без звука',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          if (currentlyMuted)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Включить уведомления'),
              onTap: () => Navigator.pop(ctx, const ChatMuteChoice.unmute()),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('На 1 час'),
              onTap: () => Navigator.pop(
                ctx,
                const ChatMuteChoice.forDuration(Duration(hours: 1)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timelapse_outlined),
              title: const Text('На 8 часов'),
              onTap: () => Navigator.pop(
                ctx,
                const ChatMuteChoice.forDuration(Duration(hours: 8)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('На 2 дня'),
              onTap: () => Navigator.pop(
                ctx,
                const ChatMuteChoice.forDuration(Duration(days: 2)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Навсегда'),
              onTap: () => Navigator.pop(ctx, const ChatMuteChoice.forever()),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
