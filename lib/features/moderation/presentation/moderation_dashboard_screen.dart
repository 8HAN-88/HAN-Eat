import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/moderation_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

/// Панель модератора: сводка и переход в очередь.
class ModerationDashboardScreen extends StatefulWidget {
  const ModerationDashboardScreen({super.key});

  @override
  State<ModerationDashboardScreen> createState() =>
      _ModerationDashboardScreenState();
}

class _ModerationDashboardScreenState extends State<ModerationDashboardScreen> {
  ModerationDashboard? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ModerationService.fetchDashboard();
      if (mounted) {
        setState(() {
          _data = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = userVisibleError(e, fallback: 'Не удалось загрузить');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Модерация'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Не удалось загрузить',
                  subtitle: _error,
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            context.push(ModerationQueueRoute.path),
                        icon: const Icon(Icons.inbox_outlined),
                        label: Text(
                          'Очередь модерации (${_data!.pendingTotal})',
                        ),
                      ),
                      const SizedBox(height: 24),
                      _StatGrid(data: _data!),
                      const SizedBox(height: 24),
                      Text(
                        'Недавние действия',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_data!.recentActions.isEmpty)
                        const Text('Пока нет записей в журнале')
                      else
                        ..._data!.recentActions.map(
                          (a) => ListTile(
                            dense: true,
                            leading: Icon(_iconForAction(a.action)),
                            title: Text(a.action),
                            subtitle: Text(
                              [
                                if (a.contentType != null)
                                  '${a.contentType} #${a.contentId}',
                                if (a.createdAt != null) a.createdAt!,
                              ].join(' · '),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  IconData _iconForAction(String action) {
    switch (action) {
      case 'approve':
        return Icons.check_circle_outline;
      case 'reject':
        return Icons.cancel_outlined;
      case 'warn_user':
        return Icons.warning_amber_outlined;
      case 'ban_user':
        return Icons.block;
      default:
        return Icons.history;
    }
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.data});

  final ModerationDashboard data;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatCard('В очереди', '${data.pendingTotal}'),
      _StatCard('AI-флаги', '${data.pendingAutoFlagged}'),
      _StatCard('Жалобы', '${data.pendingReported}'),
      _StatCard('Жалоб / 7 дн', '${data.reportsLast7d}'),
      _StatCard('Shadow', '${data.shadowUsers}'),
      _StatCard('Баны', '${data.bannedUsers}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: items,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
