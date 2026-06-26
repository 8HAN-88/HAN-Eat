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
  });

  final StarsBalance balance;
  final List<StarTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final income = transactions
        .where((tx) => WalletFilter.income.matches(tx.type, tx.amount))
        .fold<int>(0, (sum, tx) => sum + tx.amount);
    final sales = transactions.where((tx) => tx.type == 'content_sale').length;
    final donations =
        transactions.where((tx) => tx.type == 'donation_received').length;
    final subscriptions = transactions
        .where((tx) => tx.type == 'channel_subscription_received')
        .length;

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
                    'Монетизация автора',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CreatorMetric(label: 'Доход', value: '+$income ★'),
                _CreatorMetric(
                  label: 'Доступно',
                  value: '${balance.creatorAvailableStars} ★',
                ),
                _CreatorMetric(
                  label: 'Ожидает',
                  value: '${balance.creatorPendingStars} ★',
                ),
                _CreatorMetric(label: 'Продажи', value: '$sales'),
                _CreatorMetric(label: 'Донаты', value: '$donations'),
                _CreatorMetric(label: 'Подписки', value: '$subscriptions'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Создавайте платные посты и каналы, принимайте донаты и следите за доходом здесь.',
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
        return type == 'content_purchase' || type == 'channel_subscription';
      case WalletFilter.donations:
        return type == 'donation' || type == 'donation_received';
      case WalletFilter.income:
        return amount > 0 &&
            (type == 'content_sale' ||
                type == 'donation_received' ||
                type == 'channel_subscription_received');
      case WalletFilter.boosts:
        return type == 'boost';
    }
  }
}
