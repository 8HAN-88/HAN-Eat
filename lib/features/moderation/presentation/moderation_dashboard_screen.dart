import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/moderation_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _formatIsoToLocalShort(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return '-';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  return '${_two(local.day)}.${_two(local.month)} ${_two(local.hour)}:${_two(local.minute)}';
}

String _formatEpochToLocalShort(int? epochSeconds) {
  if (epochSeconds == null || epochSeconds <= 0) return '-';
  final local = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000).toLocal();
  return '${_two(local.day)}.${_two(local.month)} ${_two(local.hour)}:${_two(local.minute)}';
}

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
  bool _webhookActionLoading = false;
  bool _webhookOpsLoading = false;
  bool _webhookOpsHasMore = false;
  int _webhookOpsOffset = 0;
  bool _deadLettersLoading = false;
  bool _deadLettersHasMore = false;
  int _deadLettersOffset = 0;
  String _deadLettersQuery = '';
  List<BotWebhookDeadLetterItem> _deadLetters = const [];
  final Set<String> _selectedDeadTaskIds = <String>{};
  String? _error;
  String _webhookOpsQuery = '';
  String? _webhookOpsEventType;
  List<BotWebhookOperation> _webhookOps = const [];

  bool get _canManageWebhookQueue =>
      AuthService.instance.currentUser?.isAdmin ?? false;

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
          _webhookOps = d.botWebhookRecentOps;
          _webhookOpsOffset = d.botWebhookRecentOps.length;
          _webhookOpsHasMore = d.botWebhookRecentOps.length >= 20;
          _loading = false;
        });
      }
      if (mounted) {
        await _loadMoreWebhookOps(reset: true);
        if (_canManageWebhookQueue) {
          await _loadDeadLetters(reset: true);
        }
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

  Future<void> _runWebhookAction(
    Future<BotWebhookQueueStats> Function() action,
    String successMessage,
  ) async {
    if (_webhookActionLoading || _data == null) return;
    setState(() => _webhookActionLoading = true);
    try {
      final stats = await action();
      if (!mounted) return;
      setState(() {
        _data = _data!.copyWith(botWebhookQueue: stats);
      });
      await _loadMoreWebhookOps(reset: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось выполнить действие'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(
              _runWebhookAction(action, successMessage),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _webhookActionLoading = false);
      }
    }
  }

  List<BotWebhookOperation> _filteredWebhookOps() {
    return _webhookOps;
  }

  Future<void> _applyWebhookOpsFilters() async {
    await _loadMoreWebhookOps(reset: true);
  }

  Future<void> _loadMoreWebhookOps({bool reset = false}) async {
    if (_webhookOpsLoading) return;
    if (!reset && !_webhookOpsHasMore) return;
    setState(() => _webhookOpsLoading = true);
    try {
      final page = await ModerationService.fetchWebhookOperations(
        limit: 20,
        offset: reset ? 0 : _webhookOpsOffset,
        query: _webhookOpsQuery,
        eventType: _webhookOpsEventType,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _webhookOps = page.items;
          _webhookOpsOffset = page.items.length;
        } else {
          final merged = [..._webhookOps, ...page.items];
          final byId = <int, BotWebhookOperation>{};
          for (final item in merged) {
            byId[item.id] = item;
          }
          _webhookOps = byId.values.toList(growable: false);
          _webhookOpsOffset = _webhookOps.length;
        }
        _webhookOpsHasMore = page.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      if (reset && _webhookOps.isEmpty) {
        setState(() => _webhookOpsHasMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось загрузить операции'),
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _loadMoreWebhookOps(reset: true),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _webhookOpsLoading = false);
    }
  }

  Future<void> _exportWebhookOps() async {
    try {
      final export = await ModerationService.exportWebhookOperations(
        query: _webhookOpsQuery,
        eventType: _webhookOpsEventType,
      );
      if (export.content.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет операций для экспорта')),
        );
        return;
      }
      final content = export.content;
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            export.truncated
                ? 'Скопировано ${export.count} операций (обрезано по лимиту)'
                : 'Скопировано ${export.count} операций',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось экспортировать операции'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_exportWebhookOps()),
          ),
        ),
      );
    }
  }

  Future<void> _exportWebhookIncidentReport() async {
    try {
      final export = await ModerationService.exportWebhookIncidentReport(
        query: _webhookOpsQuery,
        eventType: _webhookOpsEventType,
      );
      if (export.content.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет данных для incident report')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: export.content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            export.truncated
                ? 'Incident report скопирован (${export.count} ops, обрезано)'
                : 'Incident report скопирован (${export.count} ops)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось экспортировать incident report'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_exportWebhookIncidentReport()),
          ),
        ),
      );
    }
  }

  Future<void> _loadDeadLetters({bool reset = false}) async {
    if (!_canManageWebhookQueue || _deadLettersLoading) return;
    if (!reset && !_deadLettersHasMore) return;
    setState(() => _deadLettersLoading = true);
    try {
      final page = await ModerationService.fetchWebhookDeadLetters(
        limit: 25,
        offset: reset ? 0 : _deadLettersOffset,
        query: _deadLettersQuery,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _deadLetters = page.items;
          _deadLettersOffset = page.items.length;
          _selectedDeadTaskIds.clear();
        } else {
          final merged = [..._deadLetters, ...page.items];
          final byTaskId = <String, BotWebhookDeadLetterItem>{};
          for (final item in merged) {
            if (item.taskId.isNotEmpty) {
              byTaskId[item.taskId] = item;
            }
          }
          _deadLetters = byTaskId.values.toList(growable: false);
          _deadLettersOffset = _deadLetters.length;
        }
        _deadLettersHasMore = page.hasMore;
        if (_data != null && page.stats != null) {
          _data = _data!.copyWith(botWebhookQueue: page.stats);
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (reset) {
        setState(() {
          _deadLetters = const [];
          _deadLettersHasMore = false;
          _selectedDeadTaskIds.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _deadLettersLoading = false);
      }
    }
  }

  Future<void> _applyDeadLetterFilters() async {
    await _loadDeadLetters(reset: true);
  }

  Future<void> _requeueSelectedDeadLetters() async {
    if (_webhookActionLoading || _selectedDeadTaskIds.isEmpty) return;
    final selected = _selectedDeadTaskIds.toList(growable: false);
    await _runWebhookAction(
      () => ModerationService.requeueWebhookDeadLetters(
        limit: selected.length,
        taskIds: selected,
      ),
      'Выбранные dead-letter задачи отправлены в очередь',
    );
    if (!mounted) return;
    await _loadDeadLetters(reset: true);
  }

  Future<void> _requeueDeadLettersPreset({
    String? dropReason,
    bool useCurrentFilter = false,
  }) async {
    if (_webhookActionLoading) return;
    final query = useCurrentFilter ? _deadLettersQuery.trim() : null;
    await _runWebhookAction(
      () => ModerationService.requeueWebhookDeadLetters(
        limit: 300,
        query: (query == null || query.isEmpty) ? null : query,
        dropReason: dropReason,
      ),
      dropReason == null
          ? 'Отфильтрованные dead-letter задачи отправлены в очередь'
          : 'Dead-letter задачи ($dropReason) отправлены в очередь',
    );
    if (!mounted) return;
    await _loadDeadLetters(reset: true);
  }

  Future<bool> _confirmDangerAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
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
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push(MiniAppsModerationRoute.path),
                        icon: const Icon(Icons.apps_outlined),
                        label: const Text('Модерация mini apps'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.push(AdsReviewRoute.path),
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('Модерация рекламы'),
                      ),
                      const SizedBox(height: 24),
                      _StatGrid(data: _data!),
                      if (_data!.botWebhookQueue != null) ...[
                        const SizedBox(height: 12),
                        _WebhookQueueCard(
                          stats: _data!.botWebhookQueue!,
                          alerts: _data!.botWebhookAlerts,
                          recentOps: _filteredWebhookOps(),
                          opsQuery: _webhookOpsQuery,
                          onOpsQueryChanged: (value) =>
                              setState(() => _webhookOpsQuery = value),
                          opsEventType: _webhookOpsEventType,
                          onOpsEventTypeChanged: (value) =>
                              setState(() => _webhookOpsEventType = value),
                          onApplyOpsFilters: _applyWebhookOpsFilters,
                          onExportOps: _exportWebhookOps,
                          onExportIncidentReport: _exportWebhookIncidentReport,
                          opsLoading: _webhookOpsLoading,
                          opsHasMore: _webhookOpsHasMore,
                          onLoadMoreOps: _loadMoreWebhookOps,
                          deadLetters: _deadLetters,
                          deadLettersQuery: _deadLettersQuery,
                          onDeadLettersQueryChanged: (value) =>
                              setState(() => _deadLettersQuery = value),
                          onApplyDeadLetterFilters: _applyDeadLetterFilters,
                          deadLettersLoading: _deadLettersLoading,
                          deadLettersHasMore: _deadLettersHasMore,
                          onLoadMoreDeadLetters: () => _loadDeadLetters(),
                          selectedDeadTaskIds: _selectedDeadTaskIds,
                          onToggleDeadTask: (taskId, selected) {
                            setState(() {
                              if (!selected || taskId.trim().isEmpty) {
                                _selectedDeadTaskIds.remove(taskId);
                              } else {
                                _selectedDeadTaskIds.add(taskId);
                              }
                            });
                          },
                          onRequeueSelectedDeadLetters: _requeueSelectedDeadLetters,
                          onRequeueMaxAttempts: () => _requeueDeadLettersPreset(
                            dropReason: 'max_attempts_exhausted',
                          ),
                          onRequeueRateLimited: () => _requeueDeadLettersPreset(
                            dropReason: 'rate_limited_per_bot',
                          ),
                          onRequeueFiltered: () => _requeueDeadLettersPreset(
                            useCurrentFilter: true,
                          ),
                          loading: _webhookActionLoading,
                          controlsEnabled: _canManageWebhookQueue,
                          onPromoteDelayed: () => _runWebhookAction(
                            () => ModerationService.promoteWebhookDelayed(),
                            'Delayed-задачи перенесены в очередь',
                          ),
                          onClearQueue: () => _runWebhookAction(
                            () async {
                              final confirm = await _confirmDangerAction(
                                title: 'Очистить webhook-очередь?',
                                message:
                                    'Будут удалены активные задачи очереди. Используйте только при инциденте.',
                                confirmLabel: 'Очистить очередь',
                              );
                              if (!confirm) return _data!.botWebhookQueue!;
                              return ModerationService.clearWebhookQueue();
                            },
                            'Webhook-очередь очищена',
                          ),
                          onResetMetrics: () => _runWebhookAction(
                            ModerationService.resetWebhookMetrics,
                            'Метрики webhook-очереди сброшены',
                          ),
                          onRequeueDropped: () => _runWebhookAction(
                            () => ModerationService.requeueWebhookDeadLetters(),
                            'Dropped-задачи возвращены в очередь',
                          ),
                          onClearDropped: () => _runWebhookAction(
                            () async {
                              final confirm = await _confirmDangerAction(
                                title: 'Очистить dead-letter?',
                                message:
                                    'Это удалит накопленные dropped-задачи без повторной доставки.',
                                confirmLabel: 'Очистить dead-letter',
                              );
                              if (!confirm) return _data!.botWebhookQueue!;
                              return ModerationService.clearWebhookDeadLetters();
                            },
                            'Dead-letter очищен',
                          ),
                          onRunRecoveryPlaybook: () => _runWebhookAction(
                            () async {
                              final confirm = await _confirmDangerAction(
                                title: 'Запустить recovery playbook?',
                                message:
                                    'Система выполнит requeue dead-letter и promote delayed. Запускать при деградации доставки.',
                                confirmLabel: 'Запустить recovery',
                              );
                              if (!confirm) return _data!.botWebhookQueue!;
                              return ModerationService.runWebhookRecoveryPlaybook();
                            },
                            'Recovery playbook выполнен',
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Недавние действия',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_data!.recentActions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Пока нет записей в журнале'),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Обновить'),
                              ),
                            ],
                          ),
                        )
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
                                if (a.createdAt != null)
                                  _formatIsoToLocalShort(a.createdAt),
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

class _WebhookQueueCard extends StatelessWidget {
  const _WebhookQueueCard({
    required this.stats,
    required this.alerts,
    required this.recentOps,
    required this.opsQuery,
    required this.onOpsQueryChanged,
    required this.opsEventType,
    required this.onOpsEventTypeChanged,
    required this.onApplyOpsFilters,
    required this.onExportOps,
    required this.onExportIncidentReport,
    required this.opsLoading,
    required this.opsHasMore,
    required this.onLoadMoreOps,
    required this.deadLetters,
    required this.deadLettersQuery,
    required this.onDeadLettersQueryChanged,
    required this.onApplyDeadLetterFilters,
    required this.deadLettersLoading,
    required this.deadLettersHasMore,
    required this.onLoadMoreDeadLetters,
    required this.selectedDeadTaskIds,
    required this.onToggleDeadTask,
    required this.onRequeueSelectedDeadLetters,
    required this.onRequeueMaxAttempts,
    required this.onRequeueRateLimited,
    required this.onRequeueFiltered,
    required this.loading,
    required this.controlsEnabled,
    required this.onPromoteDelayed,
    required this.onClearQueue,
    required this.onResetMetrics,
    required this.onRequeueDropped,
    required this.onClearDropped,
    required this.onRunRecoveryPlaybook,
  });

  final BotWebhookQueueStats stats;
  final BotWebhookAlerts? alerts;
  final List<BotWebhookOperation> recentOps;
  final String opsQuery;
  final ValueChanged<String> onOpsQueryChanged;
  final String? opsEventType;
  final ValueChanged<String?> onOpsEventTypeChanged;
  final Future<void> Function() onApplyOpsFilters;
  final Future<void> Function() onExportOps;
  final Future<void> Function() onExportIncidentReport;
  final bool opsLoading;
  final bool opsHasMore;
  final Future<void> Function() onLoadMoreOps;
  final List<BotWebhookDeadLetterItem> deadLetters;
  final String deadLettersQuery;
  final ValueChanged<String> onDeadLettersQueryChanged;
  final Future<void> Function() onApplyDeadLetterFilters;
  final bool deadLettersLoading;
  final bool deadLettersHasMore;
  final Future<void> Function() onLoadMoreDeadLetters;
  final Set<String> selectedDeadTaskIds;
  final void Function(String taskId, bool selected) onToggleDeadTask;
  final Future<void> Function() onRequeueSelectedDeadLetters;
  final Future<void> Function() onRequeueMaxAttempts;
  final Future<void> Function() onRequeueRateLimited;
  final Future<void> Function() onRequeueFiltered;
  final bool loading;
  final bool controlsEnabled;
  final Future<void> Function() onPromoteDelayed;
  final Future<void> Function() onClearQueue;
  final Future<void> Function() onResetMetrics;
  final Future<void> Function() onRequeueDropped;
  final Future<void> Function() onClearDropped;
  final Future<void> Function() onRunRecoveryPlaybook;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatCard('Webhook queue', '${stats.queueDepth}'),
      _StatCard('Delayed', '${stats.delayedDepth}'),
      _StatCard('Dead-letter', '${stats.deadDepth}'),
      _StatCard('Sent', '${stats.sentTotal}'),
      _StatCard('Failed', '${stats.failedTotal}'),
      _StatCard('Retried', '${stats.retriedTotal}'),
      _StatCard('Dropped', '${stats.droppedTotal}'),
      _StatCard('Throttled', '${stats.throttledTotal}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bot Webhook Delivery',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (stats.redisStub)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Redis stub mode: метрики приблизительные',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if ((alerts?.items ?? const []).isNotEmpty) ...[
              const SizedBox(height: 8),
              ...alerts!.items.take(4).map(
                    (a) => Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: a.severity == 'critical'
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            a.severity == 'critical'
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline_rounded,
                            size: 16,
                            color: a.severity == 'critical'
                                ? Theme.of(context).colorScheme.onErrorContainer
                                : Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${a.message}: ${a.value} (threshold ${a.threshold})',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: a.severity == 'critical'
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: items,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !controlsEnabled || loading ? null : onPromoteDelayed,
                  icon: const Icon(Icons.playlist_add_check_circle_outlined),
                  label: const Text('Promote delayed'),
                ),
                FilledButton.icon(
                  onPressed: !controlsEnabled || loading ? null : onRunRecoveryPlaybook,
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text('Run recovery playbook'),
                ),
                OutlinedButton.icon(
                  onPressed: !controlsEnabled || loading ? null : onResetMetrics,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset metrics'),
                ),
                OutlinedButton.icon(
                  onPressed: !controlsEnabled || loading ? null : onClearQueue,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear queue'),
                ),
                OutlinedButton.icon(
                  onPressed: !controlsEnabled || loading ? null : onRequeueDropped,
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Requeue dropped'),
                ),
                OutlinedButton.icon(
                  onPressed: !controlsEnabled || loading ? null : onClearDropped,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear dead-letter'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _WebhookRunbookSection(
              stats: stats,
              loading: loading,
              controlsEnabled: controlsEnabled,
              onCopyIncident: onExportIncidentReport,
              onRequeueMaxAttempts: onRequeueMaxAttempts,
              onRequeueRateLimited: onRequeueRateLimited,
              onPromoteDelayed: onPromoteDelayed,
              onRunRecoveryPlaybook: onRunRecoveryPlaybook,
            ),
            if (!controlsEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Управление доступно только администратору',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (controlsEnabled) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final visibleTaskIds = deadLetters
                      .map((item) => item.taskId.trim())
                      .where((taskId) => taskId.isNotEmpty)
                      .toList(growable: false);
                  final selectedVisibleCount = visibleTaskIds
                      .where(selectedDeadTaskIds.contains)
                      .length;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: visibleTaskIds.isEmpty
                            ? null
                            : () {
                                final shouldSelectAll =
                                    selectedVisibleCount < visibleTaskIds.length;
                                for (final taskId in visibleTaskIds) {
                                  onToggleDeadTask(taskId, shouldSelectAll);
                                }
                              },
                        icon: Icon(
                          selectedVisibleCount == visibleTaskIds.length &&
                                  visibleTaskIds.isNotEmpty
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                        ),
                        label: Text(
                          selectedVisibleCount == visibleTaskIds.length &&
                                  visibleTaskIds.isNotEmpty
                              ? 'Unselect page'
                              : 'Select page',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: selectedDeadTaskIds.isEmpty
                            ? null
                            : () {
                                for (final taskId in selectedDeadTaskIds.toList()) {
                                  onToggleDeadTask(taskId, false);
                                }
                              },
                        icon: const Icon(Icons.deselect_outlined),
                        label: const Text('Clear selected'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dead-letter tasks',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (selectedDeadTaskIds.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: loading ? null : onRequeueSelectedDeadLetters,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('Requeue selected (${selectedDeadTaskIds.length})'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: loading ? null : onRequeueMaxAttempts,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Requeue max_attempts'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: loading ? null : onRequeueRateLimited,
                    icon: const Icon(Icons.speed_outlined),
                    label: const Text('Requeue rate_limited'),
                  ),
                  OutlinedButton.icon(
                    onPressed: loading ? null : onRequeueFiltered,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Requeue filtered'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  final reasons = deadLetters
                      .map((item) => item.dropReason.trim())
                      .where((reason) => reason.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
                  if (reasons.isEmpty) return const SizedBox.shrink();
                  return Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: reasons
                        .take(4)
                        .map(
                          (reason) => ActionChip(
                            label: Text(reason),
                            onPressed: () {
                              onDeadLettersQueryChanged(reason);
                              onApplyDeadLetterFilters();
                            },
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('dead-letters-query-$deadLettersQuery'),
                      initialValue: deadLettersQuery,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Фильтр: task_id / bot_id / reason',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                      onChanged: onDeadLettersQueryChanged,
                      onFieldSubmitted: (_) => onApplyDeadLetterFilters(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: onApplyDeadLetterFilters,
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (deadLetters.isEmpty && !deadLettersLoading)
                Text(
                  'Dead-letter пуст',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ...deadLetters.take(8).map(
                      (item) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectedDeadTaskIds.contains(item.taskId),
                        onChanged: (selected) =>
                            onToggleDeadTask(item.taskId, selected == true),
                        title: Text(
                          item.taskId.isEmpty ? '(no task_id)' : item.taskId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            'bot:${item.botId ?? '-'}',
                            item.updateType.isEmpty ? 'unknown' : item.updateType,
                            item.dropReason.isEmpty ? 'drop:unknown' : item.dropReason,
                            'dropped:${_formatEpochToLocalShort(item.droppedAt)}',
                          ].join(' · '),
                        ),
                      ),
                    ),
              if (deadLettersLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (deadLettersHasMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onLoadMoreDeadLetters,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load more dead-letter'),
                  ),
                ),
            ],
            if (recentOps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent webhook ops',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onExportOps,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: onExportIncidentReport,
                    icon: const Icon(Icons.warning_amber_outlined, size: 16),
                    label: const Text('Incident'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: opsQuery,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Фильтр: event / actor',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: onOpsQueryChanged,
                onFieldSubmitted: (_) => onApplyOpsFilters(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: opsEventType,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Event type',
                      ),
                      items: const [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'bot_webhook_recovery_playbook_run',
                          child: Text('recovery_playbook'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'bot_webhook_queue_clear',
                          child: Text('queue_clear'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'bot_webhook_dead_letter_requeue',
                          child: Text('dead_letter_requeue'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'bot_webhook_dead_letter_clear',
                          child: Text('dead_letter_clear'),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'bot_webhook_metrics_reset',
                          child: Text('metrics_reset'),
                        ),
                      ],
                      onChanged: onOpsEventTypeChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: onApplyOpsFilters,
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...recentOps
                  .take(7)
                  .map(
                    (op) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(op.eventType),
                      subtitle: Text(
                        [
                          if ((op.actorName ?? '').trim().isNotEmpty) op.actorName!,
                          if ((op.actorUsername ?? '').trim().isNotEmpty)
                            '@${op.actorUsername}',
                          if ((op.createdAt ?? '').trim().isNotEmpty)
                            _formatIsoToLocalShort(op.createdAt),
                        ].join(' · '),
                      ),
                    ),
                  ),
              if (opsLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (opsHasMore)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onLoadMoreOps,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load more'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WebhookRunbookSection extends StatelessWidget {
  const _WebhookRunbookSection({
    required this.stats,
    required this.loading,
    required this.controlsEnabled,
    required this.onCopyIncident,
    required this.onRequeueMaxAttempts,
    required this.onRequeueRateLimited,
    required this.onPromoteDelayed,
    required this.onRunRecoveryPlaybook,
  });

  final BotWebhookQueueStats stats;
  final bool loading;
  final bool controlsEnabled;
  final Future<void> Function() onCopyIncident;
  final Future<void> Function() onRequeueMaxAttempts;
  final Future<void> Function() onRequeueRateLimited;
  final Future<void> Function() onPromoteDelayed;
  final Future<void> Function() onRunRecoveryPlaybook;

  @override
  Widget build(BuildContext context) {
    final deadBacklog = stats.deadDepth > 0 || stats.droppedTotal > 0;
    final delayedBacklog = stats.delayedDepth > 0;
    final throttling = stats.throttledTotal > 0;
    final hasIncident = deadBacklog || delayedBacklog || throttling;
    final runbookSteps = <_RunbookStepData>[
      _RunbookStepData(
        title: '1) Capture incident snapshot',
        description: 'Скопируйте incident report и зафиксируйте текущее состояние.',
        isActive: true,
        buttonLabel: 'Copy incident',
        onPressed: onCopyIncident,
      ),
      _RunbookStepData(
        title: '2) Requeue max attempts',
        description: 'Вернуть задачи после исчерпания retry-лимита.',
        isActive: deadBacklog,
        buttonLabel: 'Requeue max_attempts',
        onPressed: onRequeueMaxAttempts,
      ),
      _RunbookStepData(
        title: '3) Requeue rate limited',
        description: 'Вернуть задачи, отброшенные из-за per-bot quota.',
        isActive: throttling,
        buttonLabel: 'Requeue rate_limited',
        onPressed: onRequeueRateLimited,
      ),
      _RunbookStepData(
        title: '4) Promote delayed',
        description: 'Перенести delayed backlog в активную очередь.',
        isActive: delayedBacklog,
        buttonLabel: 'Promote delayed',
        onPressed: onPromoteDelayed,
      ),
      _RunbookStepData(
        title: '5) Recovery playbook',
        description: 'Финальный шаг массового восстановления.',
        isActive: hasIncident,
        buttonLabel: 'Run playbook',
        onPressed: onRunRecoveryPlaybook,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Incident runbook', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            hasIncident
                ? 'Есть признаки деградации. Выполняйте шаги последовательно.'
                : 'Инцидентных сигналов нет, но runbook доступен для проверки.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ...runbookSteps.map(
            (step) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                step.isActive ? Icons.priority_high_rounded : Icons.check_circle_outline,
                size: 18,
              ),
              title: Text(step.title),
              subtitle: Text(step.description),
              trailing: FilledButton.tonal(
                onPressed: !controlsEnabled || loading ? null : step.onPressed,
                child: Text(step.buttonLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunbookStepData {
  const _RunbookStepData({
    required this.title,
    required this.description,
    required this.isActive,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String description;
  final bool isActive;
  final String buttonLabel;
  final Future<void> Function() onPressed;
}
