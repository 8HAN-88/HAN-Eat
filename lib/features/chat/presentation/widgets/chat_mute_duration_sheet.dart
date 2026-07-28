import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Result of mute duration picker.
/// - `unmute`: turn notifications back on
/// - `until == null` and not unmute: mute forever
/// - otherwise mute until [until]
class ChatMuteChoice {
  const ChatMuteChoice._({required this.unmute, this.until});

  const ChatMuteChoice.unmute() : this._(unmute: true);
  const ChatMuteChoice.forever() : this._(unmute: false);
  ChatMuteChoice.forDuration(Duration duration)
      : this._(unmute: false, until: DateTime.now().add(duration));
  const ChatMuteChoice.until(DateTime until) : this._(unmute: false, until: until);

  final bool unmute;
  final DateTime? until;

  String get snackLabel {
    if (unmute) return 'Уведомления включены';
    final end = until;
    if (end == null) return 'Чат без звука';
    final remaining = end.difference(DateTime.now());
    if (remaining.inMinutes < 90) {
      return 'Без звука до ${DateFormat('HH:mm').format(end.toLocal())}';
    }
    if (remaining.inHours < 36) {
      return 'Без звука до ${DateFormat('dd.MM HH:mm').format(end.toLocal())}';
    }
    return 'Без звука до ${DateFormat('dd.MM.yyyy HH:mm').format(end.toLocal())}';
  }
}

String formatChatMuteUntilLabel(DateTime? until) {
  if (until == null) return 'без звука';
  final end = until.toLocal();
  final remaining = end.difference(DateTime.now());
  if (remaining.isNegative) return 'без звука';
  if (remaining.inMinutes < 90) {
    return 'без звука до ${DateFormat('HH:mm').format(end)}';
  }
  if (remaining.inHours < 36) {
    return 'без звука до ${DateFormat('dd.MM HH:mm').format(end)}';
  }
  return 'без звука до ${DateFormat('dd.MM.yyyy').format(end)}';
}

Future<ChatMuteChoice?> showChatMuteDurationSheet(
  BuildContext context, {
  required bool currentlyMuted,
  DateTime? mutedUntil,
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
          if (currentlyMuted) ...[
            if (mutedUntil != null)
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: Text(
                  'Сейчас: ${formatChatMuteUntilLabel(mutedUntil)}',
                ),
                subtitle: Text(
                  DateFormat('dd.MM.yyyy HH:mm').format(mutedUntil.toLocal()),
                ),
              )
            else
              const ListTile(
                leading: Icon(Icons.notifications_off_outlined),
                title: Text('Сейчас: без звука навсегда'),
              ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Включить уведомления'),
              onTap: () => Navigator.pop(ctx, const ChatMuteChoice.unmute()),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Изменить срок',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('На 1 час'),
            onTap: () => Navigator.pop(
              ctx,
              ChatMuteChoice.forDuration(const Duration(hours: 1)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timelapse_outlined),
            title: const Text('На 8 часов'),
            onTap: () => Navigator.pop(
              ctx,
              ChatMuteChoice.forDuration(const Duration(hours: 8)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('На 2 дня'),
            onTap: () => Navigator.pop(
              ctx,
              ChatMuteChoice.forDuration(const Duration(days: 2)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Выбрать дату и время…'),
            onTap: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: ctx,
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
                initialDate: now.add(const Duration(hours: 1)),
              );
              if (date == null || !ctx.mounted) return;
              final time = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(
                  now.add(const Duration(hours: 1)),
                ),
              );
              if (time == null || !ctx.mounted) return;
              var until = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
              if (!until.isAfter(now.add(const Duration(minutes: 1)))) {
                until = now.add(const Duration(minutes: 5));
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx, ChatMuteChoice.until(until));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Навсегда'),
            onTap: () => Navigator.pop(ctx, const ChatMuteChoice.forever()),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
