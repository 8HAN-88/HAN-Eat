import 'package:flutter/material.dart';

/// Подсказка про свайп и папки в inbox чатов.
class ChatsHubGesturesHint extends StatelessWidget {
  const ChatsHubGesturesHint({
    super.key,
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.swipe_left_outlined,
            color: scheme.onSecondaryContainer,
          ),
          title: Text(
            'Свайп влево — архив, без звука или удаление. '
            'Удержите чат → «Добавить в папку».',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
          trailing: IconButton(
            tooltip: 'Скрыть',
            icon: const Icon(Icons.close, size: 20),
            onPressed: onDismiss,
          ),
        ),
      ),
    );
  }
}
