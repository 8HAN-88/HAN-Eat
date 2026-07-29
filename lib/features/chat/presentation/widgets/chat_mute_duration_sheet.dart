import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Result of mute duration picker.
/// - `unmute`: turn notifications back on
/// - `until == null` and not unmute: mute forever
/// - otherwise mute until [until]
/// - [muteMentions]: when true, notify_mode=none (fully silent)
class ChatMuteChoice {
  const ChatMuteChoice._({
    required this.unmute,
    this.until,
    this.muteMentions = false,
  });

  const ChatMuteChoice.unmute() : this._(unmute: true);
  const ChatMuteChoice.forever({bool muteMentions = false})
      : this._(unmute: false, muteMentions: muteMentions);
  ChatMuteChoice.forDuration(
    Duration duration, {
    bool muteMentions = false,
  }) : this._(
          unmute: false,
          until: DateTime.now().add(duration),
          muteMentions: muteMentions,
        );
  const ChatMuteChoice.until(
    DateTime until, {
    bool muteMentions = false,
  }) : this._(unmute: false, until: until, muteMentions: muteMentions);

  final bool unmute;
  final DateTime? until;

  /// Fully silent including @mentions (`notify_mode=none`).
  final bool muteMentions;

  String get notifyMode => unmute
      ? 'all'
      : (muteMentions ? 'none' : 'mentions');

  String get snackLabel {
    if (unmute) return 'Уведомления включены';
    final silentMentions = muteMentions ? ' · без упоминаний' : '';
    final end = until;
    if (end == null) return 'Чат без звука$silentMentions';
    final remaining = end.difference(DateTime.now());
    if (remaining.inMinutes < 90) {
      return 'Без звука до ${DateFormat('HH:mm').format(end.toLocal())}$silentMentions';
    }
    if (remaining.inHours < 36) {
      return 'Без звука до ${DateFormat('dd.MM HH:mm').format(end.toLocal())}$silentMentions';
    }
    return 'Без звука до ${DateFormat('dd.MM.yyyy HH:mm').format(end.toLocal())}$silentMentions';
  }
}

String formatChatMuteUntilLabel(
  DateTime? until, {
  String notifyMode = 'mentions',
}) {
  final modeSuffix = notifyMode == 'none' ? ' · без @' : '';
  if (until == null) return 'без звука$modeSuffix';
  final end = until.toLocal();
  final remaining = end.difference(DateTime.now());
  if (remaining.isNegative) return 'без звука$modeSuffix';
  if (remaining.inMinutes < 90) {
    return 'без звука до ${DateFormat('HH:mm').format(end)}$modeSuffix';
  }
  if (remaining.inHours < 36) {
    return 'без звука до ${DateFormat('dd.MM HH:mm').format(end)}$modeSuffix';
  }
  return 'без звука до ${DateFormat('dd.MM.yyyy').format(end)}$modeSuffix';
}

Future<ChatMuteChoice?> showChatMuteDurationSheet(
  BuildContext context, {
  required bool currentlyMuted,
  DateTime? mutedUntil,
  String currentNotifyMode = 'all',
}) {
  var muteMentions = currentlyMuted && currentNotifyMode == 'none';
  return showModalBottomSheet<ChatMuteChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: StatefulBuilder(
        builder: (ctx, setModalState) {
          ChatMuteChoice withMentions(ChatMuteChoice base) {
            if (base.unmute) return base;
            if (base.until != null) {
              return ChatMuteChoice.until(
                base.until!,
                muteMentions: muteMentions,
              );
            }
            return ChatMuteChoice.forever(muteMentions: muteMentions);
          }

          return SingleChildScrollView(
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
                        'Сейчас: ${formatChatMuteUntilLabel(
                          mutedUntil,
                          notifyMode: currentNotifyMode,
                        )}',
                      ),
                      subtitle: Text(
                        DateFormat('dd.MM.yyyy HH:mm')
                            .format(mutedUntil.toLocal()),
                      ),
                    )
                  else
                    ListTile(
                      leading: const Icon(Icons.notifications_off_outlined),
                      title: Text(
                        currentNotifyMode == 'none'
                            ? 'Сейчас: полностью без звука'
                            : 'Сейчас: без звука (упоминания приходят)',
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Включить уведомления'),
                    onTap: () =>
                        Navigator.pop(ctx, const ChatMuteChoice.unmute()),
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
                SwitchListTile(
                  secondary: Icon(
                    muteMentions
                        ? Icons.alternate_email
                        : Icons.alternate_email_outlined,
                  ),
                  title: const Text('Без упоминаний'),
                  subtitle: Text(
                    muteMentions
                        ? 'Даже @упоминания не разбудят'
                        : 'По умолчанию @упоминания всё ещё приходят',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  value: muteMentions,
                  onChanged: (v) => setModalState(() => muteMentions = v),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('На 1 час'),
                  onTap: () => Navigator.pop(
                    ctx,
                    withMentions(
                      ChatMuteChoice.forDuration(const Duration(hours: 1)),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.timelapse_outlined),
                  title: const Text('На 8 часов'),
                  onTap: () => Navigator.pop(
                    ctx,
                    withMentions(
                      ChatMuteChoice.forDuration(const Duration(hours: 8)),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('На 2 дня'),
                  onTap: () => Navigator.pop(
                    ctx,
                    withMentions(
                      ChatMuteChoice.forDuration(const Duration(days: 2)),
                    ),
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
                    Navigator.pop(
                      ctx,
                      ChatMuteChoice.until(
                        until,
                        muteMentions: muteMentions,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Навсегда'),
                  onTap: () => Navigator.pop(
                    ctx,
                    ChatMuteChoice.forever(muteMentions: muteMentions),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ),
  );
}
