import 'package:flutter/material.dart';

import '../../../features/miniapps/data/miniapp_models.dart';
import '../../../features/miniapps/data/miniapps_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/highlighted_text.dart';

class MiniAppsModerationScreen extends StatefulWidget {
  const MiniAppsModerationScreen({super.key});

  @override
  State<MiniAppsModerationScreen> createState() =>
      _MiniAppsModerationScreenState();
}

class _MiniAppsModerationScreenState extends State<MiniAppsModerationScreen> {
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  List<MiniAppItem> _items = const [];

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
      final list = await MiniAppsService.fetchModerationQueue(
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e, fallback: 'Не удалось загрузить mini apps');
      });
    }
  }

  Future<void> _moderate(MiniAppItem app, String status) async {
    String? note;
    if (status == 'rejected') {
      note = await showDialog<String>(
        context: context,
        builder: (_) => const _ModerationNoteDialog(),
      );
      if (note == null) return;
    }
    try {
      await MiniAppsService.moderateMiniApp(
        miniAppId: app.id,
        moderationStatus: status,
        moderationNote: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Mini app одобрен'
                : status == 'rejected'
                    ? 'Mini app отклонён'
                    : 'Статус обновлён',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Модерация mini apps'),
        actions: [
          PopupMenuButton<String?>(
            initialValue: _statusFilter,
            onSelected: (value) {
              setState(() => _statusFilter = value);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String?>(
                value: null,
                child: Text('Pending + Rejected'),
              ),
              PopupMenuItem<String?>(
                value: 'pending',
                child: Text('Pending'),
              ),
              PopupMenuItem<String?>(
                value: 'approved',
                child: Text('Approved'),
              ),
              PopupMenuItem<String?>(
                value: 'rejected',
                child: Text('Rejected'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.filter_list),
            ),
          ),
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
                  icon: Icons.error_outline,
                  title: 'Ошибка загрузки',
                  subtitle: _error,
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                )
              : _items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Очередь mini apps пуста',
                      subtitle: 'Нет приложений для модерации',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final app = _items[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: HighlightedText(
                                          text: app.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      _StatusChip(status: app.moderationStatus),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  HighlightedText(
                                    text: app.shortName,
                                    leading: '@${app.botUsername} · ',
                                    style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium ??
                                        const TextStyle(fontSize: 14),
                                  ),
                                  if ((app.description ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    HighlightedText(
                                      text: app.description!.trim(),
                                      style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium ??
                                          const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _RiskChip(
                                        label:
                                            'Host: ${(app.urlHost ?? '-').isEmpty ? '-' : app.urlHost!}',
                                        level: app.urlRiskLevel,
                                      ),
                                      _RiskChip(
                                        label: 'Scheme: ${app.urlScheme ?? '-'}',
                                        level: app.urlScheme == 'https'
                                            ? 'low'
                                            : 'medium',
                                      ),
                                      if (app.urlRiskReasons.isNotEmpty)
                                        _RiskChip(
                                          label:
                                              app.urlRiskReasons.take(2).join(', '),
                                          level: app.urlRiskLevel,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    app.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                  if ((app.moderationNote ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Note: ${app.moderationNote}',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: app.moderationStatus == 'approved'
                                            ? null
                                            : () => _moderate(app, 'approved'),
                                        icon: const Icon(Icons.check),
                                        label: const Text('Approve'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: app.moderationStatus == 'rejected'
                                            ? null
                                            : () => _moderate(app, 'rejected'),
                                        icon: const Icon(Icons.close),
                                        label: const Text('Reject'),
                                      ),
                                      TextButton(
                                        onPressed: () => _moderate(app, 'pending'),
                                        child: const Text('Set Pending'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final (label, color) = switch (normalized) {
      'approved' => ('Approved', Colors.green),
      'rejected' => ('Rejected', Colors.red),
      _ => ('Pending', Colors.amber.shade800),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.label, required this.level});

  final String label;
  final String level;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (level) {
      case 'high':
        color = Colors.red;
        break;
      case 'medium':
        color = Colors.orange;
        break;
      default:
        color = Colors.green;
    }
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ModerationNoteDialog extends StatefulWidget {
  const _ModerationNoteDialog();

  @override
  State<_ModerationNoteDialog> createState() => _ModerationNoteDialogState();
}

class _ModerationNoteDialogState extends State<_ModerationNoteDialog> {
  final _controller = TextEditingController();
  static const _templates = [
    'External auth flow is unsafe / data leak risk',
    'Suspicious redirect or tracking parameters',
    'HTTP/non-HTTPS transport is not allowed',
    'Mini app content violates policy',
    'Brand impersonation / phishing risk',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Причина отклонения'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _templates
                  .map(
                    (t) => ActionChip(
                      label: Text(t, overflow: TextOverflow.ellipsis),
                      onPressed: () => setState(() => _controller.text = t),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Опишите причину (мин. 5 символов)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.length < 5) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Причина должна быть не короче 5 символов'),
                ),
              );
              return;
            }
            Navigator.pop(context, text);
          },
          child: const Text('Отклонить'),
        ),
      ],
    );
  }
}
