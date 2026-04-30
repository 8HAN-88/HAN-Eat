import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/analysis_mode.dart';
import '../../../models/search_history_entry.dart';
import '../../../services/api_service.dart';
import '../../../services/history_storage.dart';
import '../../menu/application/search_controller.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize date format with error handling
    DateFormat? dateFormat;
    try {
      dateFormat = DateFormat('dd MMM, HH:mm', 'ru');
    } catch (e) {
      // Fallback to default locale if Russian is not initialized
      dateFormat = DateFormat('dd MMM, HH:mm');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('История запросов'),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Очистить историю?'),
                      content: const Text(
                        'Это действие удалит все локальные запросы и очистит историю на сервере.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Очистить'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirm) return;
              await HistoryStorage.clear();
              await ApiService.clearServerHistory();
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          try {
            return ValueListenableBuilder(
              valueListenable: HistoryStorage.listenable(),
              builder: (context, box, _) {
                final entries = box.values.toList().cast<SearchHistoryEntry>().reversed.toList();
                if (entries.isEmpty) {
                  return Center(
                    child: Text(
                      'Запросов пока нет. Найдите блюдо в разделе "Menu".',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      tileColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      title: Text(entry.query),
                      subtitle: Text(
                        '${entry.mode.displayName} · ${dateFormat?.format(entry.timestamp) ?? entry.timestamp.toString()}',
                      ),
                      trailing: const Icon(Icons.north_west_rounded),
                      onTap: () async {
                        await ref
                            .read(searchControllerProvider.notifier)
                            .search(entry.query);
                        if (context.mounted) {
                          context.go('/');
                        }
                      },
                    );
                  },
                );
              },
            );
          } catch (e) {
            return Center(
              child: Text(
                'История не инициализирована: $e',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            );
          }
        },
      ),
    );
  }
}
