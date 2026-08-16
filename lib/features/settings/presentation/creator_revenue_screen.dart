import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/paid_features_service.dart';
import '../../../widgets/telegram_ui.dart';

class CreatorRevenueScreen extends StatefulWidget {
  const CreatorRevenueScreen({super.key});

  @override
  State<CreatorRevenueScreen> createState() => _CreatorRevenueScreenState();
}

class _CreatorRevenueScreenState extends State<CreatorRevenueScreen> {
  static const _chartModePrefKey = 'creator_revenue_chart_mode_v1';
  static const _periodPrefKey = 'creator_revenue_period_v1';
  static const _sourcePrefKey = 'creator_revenue_source_v1';
  late Future<List<StarTransaction>> _future;
  late Future<List<CreatorPayoutRequest>> _payoutsFuture;
  CreatorRevenuePeriod _period = CreatorRevenuePeriod.days30;
  CreatorRevenueSource _source = CreatorRevenueSource.all;
  CreatorRevenueChartMode _chartMode = CreatorRevenueChartMode.line;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _payoutsFuture = _loadPayouts();
    _restoreRevenuePrefs();
  }

  Future<void> _restoreRevenuePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final rawMode = prefs.getString(_chartModePrefKey);
    final rawPeriod = prefs.getString(_periodPrefKey);
    final rawSource = prefs.getString(_sourcePrefKey);

    setState(() {
      if (rawMode != null) {
        for (final mode in CreatorRevenueChartMode.values) {
          if (mode.name == rawMode) {
            _chartMode = mode;
            break;
          }
        }
      }
      if (rawPeriod != null) {
        for (final period in CreatorRevenuePeriod.values) {
          if (period.name == rawPeriod) {
            _period = period;
            break;
          }
        }
      }
      if (rawSource != null) {
        for (final source in CreatorRevenueSource.values) {
          if (source.name == rawSource) {
            _source = source;
            break;
          }
        }
      }
    });
  }

  Future<void> _setChartMode(CreatorRevenueChartMode mode) async {
    if (_chartMode == mode) return;
    setState(() => _chartMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chartModePrefKey, mode.name);
  }

  Future<void> _setPeriod(CreatorRevenuePeriod period) async {
    if (_period == period) return;
    setState(() => _period = period);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_periodPrefKey, period.name);
  }

  Future<void> _setSource(CreatorRevenueSource source) async {
    if (_source == source) return;
    setState(() => _source = source);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourcePrefKey, source.name);
  }

  Future<void> _resetFilters() async {
    final alreadyDefault = _period == CreatorRevenuePeriod.days30 &&
        _source == CreatorRevenueSource.all &&
        _chartMode == CreatorRevenueChartMode.line;
    if (alreadyDefault) return;

    setState(() {
      _period = CreatorRevenuePeriod.days30;
      _source = CreatorRevenueSource.all;
      _chartMode = CreatorRevenueChartMode.line;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_periodPrefKey, CreatorRevenuePeriod.days30.name);
    await prefs.setString(_sourcePrefKey, CreatorRevenueSource.all.name);
    await prefs.setString(_chartModePrefKey, CreatorRevenueChartMode.line.name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Фильтры сброшены')),
    );
  }

  Future<List<StarTransaction>> _load() {
    return PaidFeaturesService.getTransactions(limit: 200);
  }

  Future<List<CreatorPayoutRequest>> _loadPayouts() {
    return PaidFeaturesService.getMyPayoutRequests(limit: 40);
  }

  void _refresh() {
    setState(() {
      _future = _load();
      _payoutsFuture = _loadPayouts();
    });
  }

  String _payoutStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'В обработке';
      case 'approved':
        return 'Одобрено';
      case 'paid':
        return 'Выплачено';
      case 'rejected':
        return 'Отклонено';
      default:
        return status;
    }
  }

  Future<void> _requestPayout() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final tonController = TextEditingController();
    var method = 'rub';
    try {
      final saved = await PaidFeaturesService.getTonAddress();
      if (saved != null) tonController.text = saved;
    } catch (_) {}
    if (!mounted) {
      amountController.dispose();
      noteController.dispose();
      tonController.dispose();
      return;
    }
    final payload = await showDialog<({int amount, String? note, String method, String? ton})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Запросить выплату'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Сумма в звёздах',
                  hintText: 'например, 500',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    selected: method == 'rub',
                    label: const Text('RUB'),
                    onSelected: (_) => setLocal(() => method = 'rub'),
                  ),
                  ChoiceChip(
                    selected: method == 'ton',
                    label: const Text('TON'),
                    onSelected: (_) => setLocal(() => method = 'ton'),
                  ),
                ],
              ),
              if (method == 'ton') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: tonController,
                  decoration: const InputDecoration(
                    labelText: 'TON-адрес',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (опционально)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final amount = int.tryParse(amountController.text.trim()) ?? 0;
                if (amount <= 0) return;
                Navigator.pop(
                  ctx,
                  (
                    amount: amount,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                    method: method,
                    ton: tonController.text.trim().isEmpty
                        ? null
                        : tonController.text.trim(),
                  ),
                );
              },
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
    tonController.dispose();
    if (payload == null) return;
    try {
      if (payload.method == 'ton' && payload.ton != null) {
        await PaidFeaturesService.setTonAddress(payload.ton);
      }
      final payout = await PaidFeaturesService.requestCreatorPayout(
        amountStars: payload.amount,
        note: payload.note,
        method: payload.method,
        tonAddress: payload.ton,
      );
      if (!mounted) return;
      setState(() => _payoutsFuture = _loadPayouts());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Запрос #${payout.id} создан: ${payout.amountStars}★ (~${payout.amountRub.toStringAsFixed(2)} RUB)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  List<StarTransaction> _filteredIncomeTx(List<StarTransaction> all) {
    final start = DateTime.now().subtract(Duration(days: _period.days));
    return all.where((tx) {
      if (tx.amount <= 0) return false;
      if (!tx.createdAt.isAfter(start)) return false;
      return _source.matches(tx.type);
    }).toList();
  }

  int _sumAmount(Iterable<StarTransaction> items) =>
      items.fold<int>(0, (sum, tx) => sum + tx.amount);

  String _buildCsv(List<StarTransaction> items) {
    final b = StringBuffer()
      ..writeln('created_at,type,amount_stars,counterparty_user_id,reference_type,reference_id');
    for (final tx in items) {
      b.writeln(
        '${tx.createdAt.toIso8601String()},${tx.type},${tx.amount},'
        '${tx.counterpartyUserId ?? ''},${tx.referenceType ?? ''},${tx.referenceId ?? ''}',
      );
    }
    return b.toString();
  }

  Future<void> _shareCsvText(List<StarTransaction> items) async {
    final text = _buildCsv(items);
    await Share.share(
      text,
      subject: 'creator_revenue_${_period.days}d_${DateTime.now().toIso8601String()}',
    );
  }

  Future<void> _shareCsvFile(List<StarTransaction> items) async {
    final csv = _buildCsv(items);
    final filename = 'creator_revenue_${_period.days}d.csv';
    final file = XFile.fromData(
      Uint8List.fromList(csv.codeUnits),
      mimeType: 'text/csv',
      name: filename,
    );
    await Share.shareXFiles(
      [file],
      text: 'Отчет по доходам автора',
      subject: filename,
    );
  }

  List<_DailyRevenuePoint> _dailyRevenuePoints(List<StarTransaction> items) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _period.days - 1));
    final buckets = <DateTime, int>{};
    for (var i = 0; i < _period.days; i++) {
      final day = start.add(Duration(days: i));
      buckets[DateTime(day.year, day.month, day.day)] = 0;
    }
    for (final tx in items) {
      final day = DateTime(
        tx.createdAt.year,
        tx.createdAt.month,
        tx.createdAt.day,
      );
      if (!day.isBefore(start) && buckets.containsKey(day)) {
        buckets[day] = (buckets[day] ?? 0) + tx.amount;
      }
    }
    return buckets.entries
        .map((e) => _DailyRevenuePoint(day: e.key, amount: e.value))
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
  }

  String _txTitle(String type) {
    switch (type) {
      case 'content_sale':
        return 'Продажа контента';
      case 'donation_received':
        return 'Донат получен';
      case 'channel_subscription_received':
        return 'Подписка на канал';
      case 'paid_media_sale':
        return 'Продажа медиа';
      case 'paid_message_received':
        return 'Оплата за сообщение';
      case 'paid_reaction_received':
        return 'Платная реакция';
      case 'gift_received':
        return 'Подарок';
      case 'gift_converted':
        return 'Подарок → ★';
      case 'gift_resale_received':
        return 'Продажа подарка';
      default:
        return type;
    }
  }

  String _date(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Доходы автора'),
        actions: [
          IconButton(
            tooltip: 'Запросить выплату',
            onPressed: _requestPayout,
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(
            tooltip: 'Сбросить фильтры',
            onPressed: _resetFilters,
            icon: const Icon(Icons.filter_alt_off_rounded),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<StarTransaction>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Не удалось загрузить доходы',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final filtered = _filteredIncomeTx(snapshot.data!);
          final total = _sumAmount(filtered);
          final sales = _sumAmount(filtered.where((t) => t.type == 'content_sale'));
          final donations =
              _sumAmount(filtered.where((t) => t.type == 'donation_received'));
          final subscriptions = _sumAmount(
            filtered.where((t) => t.type == 'channel_subscription_received'),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in CreatorRevenuePeriod.values) ...[
                            ChoiceChip(
                              label: Text(p.label),
                              selected: p == _period,
                              onSelected: (_) => _setPeriod(p),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Экспорт',
                    onSelected: (value) async {
                      if (filtered.isEmpty) return;
                      if (value == 'file') {
                        await _shareCsvFile(filtered);
                      } else {
                        await _shareCsvText(filtered);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'file',
                        child: Text('Экспорт CSV файлом'),
                      ),
                      PopupMenuItem(
                        value: 'text',
                        child: Text('Поделиться CSV текстом'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.ios_share_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final source in CreatorRevenueSource.values) ...[
                      FilterChip(
                        label: Text(source.label),
                        selected: source == _source,
                        onSelected: (_) => _setSource(source),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _StatTile(label: 'Доход', value: '+$total ★'),
                      _StatTile(label: 'Контент', value: '$sales ★'),
                      _StatTile(label: 'Донаты', value: '$donations ★'),
                      _StatTile(label: 'Подписки', value: '$subscriptions ★'),
                      _StatTile(label: 'Операций', value: '${filtered.length}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Доход по дням',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final mode in CreatorRevenueChartMode.values) ...[
                            ChoiceChip(
                              label: Text(mode.label),
                              selected: _chartMode == mode,
                              onSelected: (_) => _setChartMode(mode),
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 172,
                        child: _RevenueLineChart(
                          points: _dailyRevenuePoints(filtered),
                          mode: _chartMode,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const TelegramSectionHeader(
                title: 'Выплаты',
                padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
              ),
              FutureBuilder<List<CreatorPayoutRequest>>(
                future: _payoutsFuture,
                builder: (context, payoutSnap) {
                  if (payoutSnap.hasError) {
                    return TelegramGroupedSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Не удалось загрузить выплаты',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  if (!payoutSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final payouts = payoutSnap.data!;
                  if (payouts.isEmpty) {
                    return TelegramGroupedSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Запросов на выплату пока нет',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final p in payouts)
                        TelegramGroupedSurface(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: TelegramActionRow(
                            icon: Icons.account_balance_wallet_outlined,
                            iconColor: scheme.secondary,
                            title: '${p.amountStars} ★',
                            subtitle:
                                '${_payoutStatusLabel(p.status)}${p.createdAt != null ? ' · ${_date(p.createdAt!)}' : ''}',
                            trailing: Text(
                              '~${p.amountRub.toStringAsFixed(0)} ₽',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const TelegramSectionHeader(
                title: 'Операции',
                padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
              ),
              if (filtered.isEmpty)
                TelegramGroupedSurface(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Доходных операций за период нет',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                for (final tx in filtered)
                  TelegramGroupedSurface(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: TelegramActionRow(
                      icon: Icons.payments_outlined,
                      iconColor: scheme.primary,
                      title: _txTitle(tx.type),
                      subtitle: _date(tx.createdAt),
                      trailing: Text(
                        '+${tx.amount} ★',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _txTitle(tx.type),
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Дата: ${_date(tx.createdAt)}'),
                                  Text('Сумма: +${tx.amount} ★'),
                                  if (tx.counterpartyUserId != null)
                                    Text('Контрагент: #${tx.counterpartyUserId}'),
                                  if (tx.referenceType != null)
                                    Text('Тип ссылки: ${tx.referenceType}'),
                                  if (tx.referenceId != null)
                                    Text('ID ссылки: ${tx.referenceId}'),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _DailyRevenuePoint {
  const _DailyRevenuePoint({required this.day, required this.amount});

  final DateTime day;
  final int amount;
}

class _RevenueLineChart extends StatefulWidget {
  const _RevenueLineChart({
    required this.points,
    required this.mode,
  });

  final List<_DailyRevenuePoint> points;
  final CreatorRevenueChartMode mode;

  @override
  State<_RevenueLineChart> createState() => _RevenueLineChartState();
}

class _RevenueLineChartState extends State<_RevenueLineChart> {
  int? _selectedIndex;

  int? _indexFromDx(double dx, double width) {
    final points = widget.points;
    if (points.isEmpty || width <= 0) return null;
    if (points.length == 1) return 0;
    final stepX = width / (points.length - 1);
    final raw = (dx / stepX).round();
    return raw.clamp(0, points.length - 1);
  }

  String _shortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final maxY = points.map((p) => p.amount).fold<int>(0, math.max);
    final midY = (maxY / 2).round();
    final selected = _selectedIndex != null && _selectedIndex! < points.length
        ? points[_selectedIndex!]
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = math.max(1.0, constraints.maxWidth - 48);
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$maxY',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          '$midY',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          '0',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        setState(
                          () => _selectedIndex = _indexFromDx(
                            details.localPosition.dx,
                            chartWidth,
                          ),
                        );
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(
                          () => _selectedIndex = _indexFromDx(
                            details.localPosition.dx,
                            chartWidth,
                          ),
                        );
                      },
                      child: CustomPaint(
                        painter: _RevenueLinePainter(
                          points: points,
                    mode: widget.mode,
                          lineColor: scheme.primary,
                          fillColor: scheme.primary.withValues(alpha: 0.14),
                          axisColor: scheme.outlineVariant,
                          selectedIndex: _selectedIndex,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortDate(points.first.day),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _shortDate(points.last.day),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (selected != null)
              Text(
                '${_shortDate(selected.day)}: ${selected.amount} ★',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              )
            else
              Text(
                'Тапните по графику для точного значения',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
          ],
        );
      },
    );
  }
}

class _RevenueLinePainter extends CustomPainter {
  _RevenueLinePainter({
    required this.points,
    required this.mode,
    required this.lineColor,
    required this.fillColor,
    required this.axisColor,
    this.selectedIndex,
  });

  final List<_DailyRevenuePoint> points;
  final CreatorRevenueChartMode mode;
  final Color lineColor;
  final Color fillColor;
  final Color axisColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxY = math.max(1, points.map((p) => p.amount).fold<int>(0, math.max));
    const topPad = 8.0;
    const bottomPad = 14.0;
    final h = size.height - topPad - bottomPad;
    final stepX = points.length <= 1 ? size.width : size.width / (points.length - 1);

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final midY = size.height - bottomPad - h * 0.5;
    canvas.drawLine(
      Offset(0, topPad),
      Offset(size.width, topPad),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height - bottomPad),
      Offset(size.width, size.height - bottomPad),
      axisPaint,
    );

    if (mode == CreatorRevenueChartMode.line) {
      final line = Path();
      final fill = Path();
      for (var i = 0; i < points.length; i++) {
        final x = i * stepX;
        final y = size.height - bottomPad - (points[i].amount / maxY) * h;
        if (i == 0) {
          line.moveTo(x, y);
          fill.moveTo(x, size.height - bottomPad);
          fill.lineTo(x, y);
        } else {
          line.lineTo(x, y);
          fill.lineTo(x, y);
        }
      }
      fill.lineTo(size.width, size.height - bottomPad);
      fill.close();

      canvas.drawPath(
        fill,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      final pointPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill;
      for (var i = 0; i < points.length; i++) {
        final x = i * stepX;
        final y = size.height - bottomPad - (points[i].amount / maxY) * h;
        canvas.drawCircle(Offset(x, y), 2.6, pointPaint);
      }
    } else {
      final barPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.78)
        ..style = PaintingStyle.fill;
      final barWidth = math.max(2.0, stepX * 0.62);
      for (var i = 0; i < points.length; i++) {
        final x = i * stepX;
        final y = size.height - bottomPad - (points[i].amount / maxY) * h;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x - barWidth / 2,
            y,
            x + barWidth / 2,
            size.height - bottomPad,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, barPaint);
      }
    }

    final idx = selectedIndex;
    if (idx != null && idx >= 0 && idx < points.length) {
      final x = idx * stepX;
      final y = size.height - bottomPad - (points[idx].amount / maxY) * h;
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(x, y),
        mode == CreatorRevenueChartMode.line ? 4.8 : 5.2,
        Paint()..color = lineColor,
      );
      canvas.drawCircle(
        Offset(x, y),
        mode == CreatorRevenueChartMode.line ? 7.8 : 8.8,
        Paint()
          ..color = lineColor.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.mode != mode ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}

enum CreatorRevenueChartMode {
  line('Линия'),
  bars('Столбцы');

  const CreatorRevenueChartMode(this.label);
  final String label;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

enum CreatorRevenuePeriod {
  days7(7, '7д'),
  days30(30, '30д'),
  days90(90, '90д'),
  days180(180, '180д');

  const CreatorRevenuePeriod(this.days, this.label);
  final int days;
  final String label;
}

enum CreatorRevenueSource {
  all('Все'),
  content('Контент'),
  donations('Донаты'),
  subscriptions('Подписки');

  const CreatorRevenueSource(this.label);
  final String label;

  bool matches(String type) {
    switch (this) {
      case CreatorRevenueSource.all:
        return type == 'content_sale' ||
            type == 'donation_received' ||
            type == 'channel_subscription_received' ||
            type == 'paid_media_sale' ||
            type == 'paid_message_received' ||
            type == 'paid_reaction_received' ||
            type == 'gift_received' ||
            type == 'gift_converted' ||
            type == 'gift_resale_received';
      case CreatorRevenueSource.content:
        return type == 'content_sale' || type == 'paid_media_sale';
      case CreatorRevenueSource.donations:
        return type == 'donation_received' ||
            type == 'gift_received' ||
            type == 'gift_converted' ||
            type == 'gift_resale_received' ||
            type == 'paid_reaction_received' ||
            type == 'paid_message_received';
      case CreatorRevenueSource.subscriptions:
        return type == 'channel_subscription_received';
    }
  }
}
