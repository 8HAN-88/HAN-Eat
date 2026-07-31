import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';

/// Telegram-like channel Stars giveaways manage / join screen.
class ChannelGiveawaysScreen extends StatefulWidget {
  const ChannelGiveawaysScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.canManage = false,
  });

  final int channelId;
  final String channelName;
  final bool canManage;

  @override
  State<ChannelGiveawaysScreen> createState() => _ChannelGiveawaysScreenState();
}

class _ChannelGiveawaysScreenState extends State<ChannelGiveawaysScreen> {
  bool _loading = true;
  String? _error;
  List<StarGiveaway> _items = const [];
  final Set<int> _busy = {};

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
      final items = await PaidFeaturesService.listChannelGiveaways(
        widget.channelId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  Future<void> _create() async {
    final prizeController = TextEditingController(text: '50');
    final winnersController = TextEditingController(text: '1');
    final titleController = TextEditingController();
    var hours = 24;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            final prize = int.tryParse(prizeController.text.trim()) ?? 0;
            final winners = int.tryParse(winnersController.text.trim()) ?? 0;
            final total = prize * winners;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Розыгрыш Stars',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Как в Telegram: звёзды спишутся сразу и будут разыграны между участниками.',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Название (необязательно)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: prizeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '★ каждому победителю',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: winnersController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Число победителей',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final h in const [6, 12, 24, 72, 168])
                        ChoiceChip(
                          selected: hours == h,
                          label: Text(h < 24 ? '$h ч' : '${h ~/ 24} д'),
                          onSelected: (_) => setLocal(() => hours = h),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'К списанию: $total ★',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: total > 0
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          child: const Text('Создать'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final prize = int.tryParse(prizeController.text.trim()) ?? 0;
    final winners = int.tryParse(winnersController.text.trim()) ?? 0;
    final title = titleController.text.trim();
    prizeController.dispose();
    winnersController.dispose();
    titleController.dispose();
    if (ok != true || !mounted) return;
    final confirmed = await confirmStarsSpend(
      context,
      title: 'Создать розыгрыш',
      body: 'С баланса спишется ${prize * winners} ★ в эскроу до конца розыгрыша.',
      amountStars: prize * winners,
      confirmLabel: 'Создать',
    );
    if (!confirmed || !mounted) return;
    try {
      await PaidFeaturesService.createChannelGiveaway(
        widget.channelId,
        prizeStars: prize,
        winnersCount: winners,
        durationHours: hours,
        title: title.isEmpty ? null : title,
      );
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Розыгрыш создан')),
      );
    } catch (e) {
      if (!mounted) return;
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _join(StarGiveaway g) async {
    if (_busy.contains(g.id)) return;
    setState(() => _busy.add(g.id));
    try {
      final next = await PaidFeaturesService.joinGiveaway(g.id);
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == next.id ? next : e).toList();
        _busy.remove(g.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(g.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _cancel(StarGiveaway g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить розыгрыш?'),
        content: const Text('Эскроу вернётся на баланс. Участники не получат приз.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Назад'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(g.id));
    try {
      final next = await PaidFeaturesService.cancelGiveaway(g.id);
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == next.id ? next : e).toList();
        _busy.remove(g.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(g.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _finalize(StarGiveaway g) async {
    setState(() => _busy.add(g.id));
    try {
      final next = await PaidFeaturesService.finalizeGiveaway(g.id);
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == next.id ? next : e).toList();
        _busy.remove(g.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(g.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Розыгрыши · ${widget.channelName}'),
        actions: [
          if (widget.canManage)
            IconButton(
              tooltip: 'Создать',
              onPressed: _create,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.celebration_outlined),
              label: const Text('Розыгрыш'),
            )
          : null,
      body: AppGradientBackground(
        child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Повторить')),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          64,
          24,
          24 + floatingBottomPadding(context),
        ),
        children: [
          const Icon(Icons.celebration_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            widget.canManage
                ? 'Пока нет розыгрышей. Создайте розыгрыш Stars для подписчиков.'
                : 'Активных розыгрышей нет.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        16 + floatingBottomPadding(context),
      ),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final g = _items[index];
        final busy = _busy.contains(g.id);
        final ends = DateFormat('d MMM, HH:mm', 'ru').format(g.endsAt.toLocal());
        final scheme = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.title?.trim().isNotEmpty == true
                      ? g.title!.trim()
                      : 'Розыгрыш Stars',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${g.prizeStars} ★ × ${g.winnersCount} · ${g.participantsCount} уч. · до $ends',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                Text(
                  g.isWinner
                      ? 'Вы победили!'
                      : g.joinedByMe
                          ? 'Вы участвуете'
                          : (g.isActive ? 'Можно участвовать' : g.status),
                  style: TextStyle(
                    color: g.isWinner ? scheme.primary : scheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (g.isActive && !g.joinedByMe && !widget.canManage)
                      FilledButton(
                        onPressed: busy ? null : () => unawaited(_join(g)),
                        child: const Text('Участвовать'),
                      ),
                    if (g.isActive && !g.joinedByMe && widget.canManage)
                      FilledButton.tonal(
                        onPressed: busy ? null : () => unawaited(_join(g)),
                        child: const Text('Участвовать'),
                      ),
                    if (widget.canManage && g.isActive) ...[
                      OutlinedButton(
                        onPressed: busy ? null : () => unawaited(_finalize(g)),
                        child: const Text('Завершить'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => unawaited(_cancel(g)),
                        child: const Text('Отменить'),
                      ),
                    ],
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
