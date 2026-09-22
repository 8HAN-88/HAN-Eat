import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/app_router.dart';
import '../../../services/revenue_share_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

class AdminPartnerPayoutsScreen extends StatefulWidget {
  const AdminPartnerPayoutsScreen({super.key});

  @override
  State<AdminPartnerPayoutsScreen> createState() =>
      _AdminPartnerPayoutsScreenState();
}

class _AdminPartnerPayoutsScreenState extends State<AdminPartnerPayoutsScreen> {
  bool _loading = true;
  String? _error;
  List<PartnerPayout> _items = [];

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
      final items = await RevenueShareApi.adminQueue();
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

  Future<void> _review(PartnerPayout item, {required bool approve}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Подтвердить выплату' : 'Отклонить заявку'),
        content: Text(
          approve
              ? 'Отметить ${item.amountRub} для ${item.userName ?? item.userEmail ?? 'id:${item.userId}'} как выплаченные? Перевод на СБП делается вручную.'
              : 'Вернуть ${item.amountRub} на доступный баланс?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Выплачено' : 'Отклонить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await RevenueShareApi.reviewPayout(payoutId: item.id, approve: approve);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Отмечено как выплаченное' : 'Заявка отклонена'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_review(item, approve: approve)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выплаты партнёрам'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ModerationDashboardRoute.path);
            }
          },
        ),
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
      return AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Очередь пуста',
        subtitle: 'Нет заявок на карту или СБП',
        action: FilledButton(
          onPressed: _load,
          child: const Text('Обновить'),
        ),
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
                  item.amountRub,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.userName != null && item.userName!.isNotEmpty)
                      item.userName!,
                    if (item.userEmail != null && item.userEmail!.isNotEmpty)
                      item.userEmail!,
                    if (item.phone != null && item.phone!.isNotEmpty) item.phone!,
                    if (item.recipientName != null &&
                        item.recipientName!.isNotEmpty)
                      item.recipientName!,
                    if (date.isNotEmpty) date,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _review(item, approve: false),
                        child: const Text('Отклонить'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _review(item, approve: true),
                        child: const Text('Выплачено'),
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
