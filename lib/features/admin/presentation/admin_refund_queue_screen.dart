import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:intl/intl.dart';
import '../../../services/payment_service.dart';
import '../../../widgets/app_empty_state.dart';

/// Очередь запросов на возврат (только is_admin).
class AdminRefundQueueScreen extends StatefulWidget {
  const AdminRefundQueueScreen({super.key});

  @override
  State<AdminRefundQueueScreen> createState() => _AdminRefundQueueScreenState();
}

class _AdminRefundQueueScreenState extends State<AdminRefundQueueScreen> {
  bool _loading = true;
  String? _error;
  List<AdminRefundQueueItem> _items = [];

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
      final items = await PaymentService.getAdminRefundQueue();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e, fallback: 'Не удалось загрузить очередь');
        _loading = false;
      });
    }
  }

  Future<void> _approve(AdminRefundQueueItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердить возврат'),
        content: Text(
          'Вернуть ${item.amount.toStringAsFixed(0)} ₽ пользователю '
          '${item.userEmail ?? "id:${item.id}"}?\n'
          'Операция в ЮKassa необратима.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Вернуть'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await PaymentService.adminProcessRefund(subscriptionId: item.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Возврат проведён'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reject(AdminRefundQueueItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отклонить возврат'),
        content: Text(
          'Отклонить запрос от ${item.userEmail ?? "пользователя"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await PaymentService.adminRejectRefund(subscriptionId: item.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запрос отклонён')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Возвраты'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить',
        subtitle: _error,
        action: FilledButton(
          onPressed: _load,
          child: const Text('Повторить'),
        ),
      );
    }

    if (_items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Очередь пуста',
        subtitle: 'Нет ожидающих запросов на возврат',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = _items[i];
        final date = item.createdAt != null
            ? DateFormat('d MMM yyyy HH:mm', 'ru').format(item.createdAt!)
            : '';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.userName != null) item.userName!,
                    if (item.userEmail != null) item.userEmail!,
                    '${item.amount.toStringAsFixed(0)} ₽',
                    if (date.isNotEmpty) date,
                    if (item.ticketId != null) 'тикет #${item.ticketId}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _reject(item),
                        child: const Text('Отклонить'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _approve(item),
                        child: const Text('Вернуть'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
