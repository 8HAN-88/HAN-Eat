import 'package:flutter/material.dart';

import '../../../../services/paid_features_service.dart';

class StarsBalanceCard extends StatelessWidget {
  const StarsBalanceCard({super.key, required this.balance});

  final StarsBalance balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer.withValues(alpha: 0.72),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Баланс', style: TextStyle(color: scheme.onPrimaryContainer)),
          const SizedBox(height: 8),
          Text(
            '${balance.balance} ★',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onPrimaryContainer,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Авторский баланс: ${balance.creatorAvailableStars} ★',
            style: TextStyle(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class CreatorDashboardCard extends StatelessWidget {
  const CreatorDashboardCard({
    super.key,
    required this.balance,
    required this.transactions,
    required this.period,
    required this.onPeriodChanged,
  });

  final StarsBalance balance;
  final List<StarTransaction> transactions;
  final WalletStatsPeriod period;
  final ValueChanged<WalletStatsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = CreatorMonetizationSummary.fromTransactions(
      transactions: transactions,
      period: period,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Монетизация автора (${period.label})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in WalletStatsPeriod.values) ...[
                    ChoiceChip(
                      label: Text(p.label),
                      selected: p == period,
                      onSelected: (_) => onPeriodChanged(p),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CreatorMetric(label: 'Доход', value: '+${summary.income} ★'),
                _CreatorMetric(label: 'Расход', value: '-${summary.expenseAbs} ★'),
                _CreatorMetric(label: 'Итог', value: '${summary.netStars >= 0 ? '+' : ''}${summary.netStars} ★'),
                _CreatorMetric(
                  label: 'Доступно',
                  value: '${balance.creatorAvailableStars} ★',
                ),
                _CreatorMetric(
                  label: 'Ожидает',
                  value: '${balance.creatorPendingStars} ★',
                ),
                _CreatorMetric(
                  label: 'Продажи',
                  value: '${summary.salesCount}',
                ),
                _CreatorMetric(
                  label: 'Донаты',
                  value: '${summary.donationsCount}',
                ),
                _CreatorMetric(
                  label: 'Подписки',
                  value: '${summary.subscriptionsCount}',
                ),
                _CreatorMetric(
                  label: 'Поддержали',
                  value: '${summary.uniqueSupporters}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _IncomeBreakdown(
              sales: summary.salesIncome,
              donations: summary.donationsIncome,
              subscriptions: summary.subscriptionsIncome,
            ),
            const SizedBox(height: 12),
            Text(
              summary.hint,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatorMetric extends StatelessWidget {
  const _CreatorMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
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

class _IncomeBreakdown extends StatelessWidget {
  const _IncomeBreakdown({
    required this.sales,
    required this.donations,
    required this.subscriptions,
  });

  final int sales;
  final int donations;
  final int subscriptions;

  @override
  Widget build(BuildContext context) {
    final total = sales + donations + subscriptions;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (total <= 0) {
      return Text(
        'За выбранный период доходов пока не было.',
        style: TextStyle(color: muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Источники дохода',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        _IncomeBreakdownRow(
          label: 'Платный контент',
          value: sales,
          total: total,
          color: Colors.indigo,
        ),
        const SizedBox(height: 6),
        _IncomeBreakdownRow(
          label: 'Донаты',
          value: donations,
          total: total,
          color: Colors.orange,
        ),
        const SizedBox(height: 6),
        _IncomeBreakdownRow(
          label: 'Подписки',
          value: subscriptions,
          total: total,
          color: Colors.green,
        ),
      ],
    );
  }
}

class _IncomeBreakdownRow extends StatelessWidget {
  const _IncomeBreakdownRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = total > 0 ? value / total : 0.0;
    final percent = (share * 100).toStringAsFixed(0);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            '$value ★ · $percent%',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

enum WalletFilter {
  all('Все'),
  topUps('Пополнения'),
  purchases('Покупки'),
  donations('Донаты'),
  income('Доходы'),
  boosts('Бусты');

  const WalletFilter(this.label);

  final String label;

  bool matches(String type, int amount) {
    switch (this) {
      case WalletFilter.all:
        return true;
      case WalletFilter.topUps:
        return type == 'purchase' || type == 'admin_adjust';
      case WalletFilter.purchases:
        return type == 'content_purchase' ||
            type == 'channel_subscription' ||
            type == 'paid_media_purchase' ||
            type == 'paid_message' ||
            type == 'paid_reaction' ||
            type == 'gift';
      case WalletFilter.donations:
        return type == 'donation' || type == 'donation_received';
      case WalletFilter.income:
        return amount > 0 &&
            (type == 'content_sale' ||
                type == 'donation_received' ||
                type == 'channel_subscription_received' ||
                type == 'paid_media_sale' ||
                type == 'paid_message_received' ||
                type == 'paid_reaction_received' ||
                type == 'gift_received' ||
                type == 'gift_converted');
      case WalletFilter.boosts:
        return type == 'boost';
    }
  }
}

enum WalletStatsPeriod {
  days7(7, '7д'),
  days30(30, '30д'),
  days90(90, '90д');

  const WalletStatsPeriod(this.days, this.label);

  final int days;
  final String label;
}

class CreatorMonetizationSummary {
  const CreatorMonetizationSummary({
    required this.income,
    required this.expenseAbs,
    required this.netStars,
    required this.salesCount,
    required this.donationsCount,
    required this.subscriptionsCount,
    required this.uniqueSupporters,
    required this.salesIncome,
    required this.donationsIncome,
    required this.subscriptionsIncome,
    required this.hint,
  });

  final int income;
  final int expenseAbs;
  final int netStars;
  final int salesCount;
  final int donationsCount;
  final int subscriptionsCount;
  final int uniqueSupporters;
  final int salesIncome;
  final int donationsIncome;
  final int subscriptionsIncome;
  final String hint;

  factory CreatorMonetizationSummary.fromTransactions({
    required List<StarTransaction> transactions,
    required WalletStatsPeriod period,
  }) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: period.days));
    final previousStart = start.subtract(Duration(days: period.days));
    final inCurrent = transactions.where((tx) => tx.createdAt.isAfter(start));
    final inPrevious = transactions.where(
      (tx) =>
          tx.createdAt.isAfter(previousStart) && !tx.createdAt.isAfter(start),
    );

    int incomeFor(Iterable<StarTransaction> items) => items
        .where((tx) => WalletFilter.income.matches(tx.type, tx.amount))
        .fold<int>(0, (sum, tx) => sum + tx.amount);

    int expenseFor(Iterable<StarTransaction> items) => items
        .where((tx) => tx.amount < 0)
        .fold<int>(0, (sum, tx) => sum + tx.amount.abs());

    final income = incomeFor(inCurrent);
    final expenseAbs = expenseFor(inCurrent);
    final previousIncome = incomeFor(inPrevious);
    final delta = income - previousIncome;

    int countByType(String type) =>
        inCurrent.where((tx) => tx.type == type).length;
    int incomeByType(String type) => inCurrent
        .where((tx) => tx.type == type && tx.amount > 0)
        .fold<int>(0, (sum, tx) => sum + tx.amount);

    final supporters = inCurrent
        .where((tx) => tx.amount > 0 && tx.counterpartyUserId != null)
        .map((tx) => tx.counterpartyUserId!)
        .toSet()
        .length;

    final hint = delta == 0
        ? 'Доход за период без изменений к предыдущему периоду.'
        : delta > 0
            ? 'Доход вырос на +$delta ★ к прошлому периоду.'
            : 'Доход снизился на ${delta.abs()} ★ к прошлому периоду.';

    return CreatorMonetizationSummary(
      income: income,
      expenseAbs: expenseAbs,
      netStars: income - expenseAbs,
      salesCount: countByType('content_sale'),
      donationsCount: countByType('donation_received'),
      subscriptionsCount: countByType('channel_subscription_received'),
      uniqueSupporters: supporters,
      salesIncome: incomeByType('content_sale'),
      donationsIncome: incomeByType('donation_received'),
      subscriptionsIncome: incomeByType('channel_subscription_received'),
      hint: hint,
    );
  }
}
