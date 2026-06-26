import 'package:flutter/material.dart';

import '../../../services/paid_features_service.dart';
import '../../../services/payment_service.dart';
import '../../../widgets/app_gradient_background.dart';

class StarsWalletScreen extends StatefulWidget {
  const StarsWalletScreen({super.key});

  @override
  State<StarsWalletScreen> createState() => _StarsWalletScreenState();
}

class _StarsWalletScreenState extends State<StarsWalletScreen> {
  late Future<_WalletData> _future;
  bool _checkoutLoading = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_WalletData> _load() async {
    final results = await Future.wait([
      PaidFeaturesService.getBalance(),
      PaidFeaturesService.getStarPackages(),
      PaidFeaturesService.getTransactions(),
    ]);
    return _WalletData(
      balance: results[0] as StarsBalance,
      packages: results[1] as List<StarPackage>,
      transactions: results[2] as List<StarTransaction>,
    );
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _buyPackage(StarPackage package) async {
    if (_checkoutLoading) return;
    setState(() => _checkoutLoading = true);
    try {
      final checkout =
          await PaidFeaturesService.createStarsCheckout(package.id);
      await PaymentService.openCheckout(checkout.url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _checkoutLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Звёзды и кошелёк'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<_WalletData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Не удалось загрузить кошелёк',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _BalanceCard(balance: data.balance),
                  const SizedBox(height: 18),
                  Text(
                    'Купить звёзды',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  for (final package in data.packages)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.stars_rounded),
                        title: Text(package.title),
                        subtitle: Text('${package.priceRub} ₽'),
                        trailing: FilledButton(
                          onPressed:
                              _checkoutLoading ? null : () => _buyPackage(package),
                          child: const Text('Купить'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'История',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  if (data.transactions.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Операций пока нет',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    for (final tx in data.transactions)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            tx.amount >= 0
                                ? Icons.add_circle_outline_rounded
                                : Icons.remove_circle_outline_rounded,
                          ),
                          title: Text(_txTitle(tx.type)),
                          subtitle: Text(_date(tx.createdAt)),
                          trailing: Text(
                            '${tx.amount > 0 ? '+' : ''}${tx.amount} ★',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: tx.amount >= 0
                                  ? scheme.primary
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _txTitle(String type) {
    switch (type) {
      case 'purchase':
        return 'Покупка звёзд';
      case 'content_purchase':
        return 'Покупка контента';
      case 'content_sale':
        return 'Продажа контента';
      case 'donation':
        return 'Донат';
      case 'donation_received':
        return 'Донат получен';
      case 'boost':
        return 'Буст поста';
      case 'channel_subscription':
        return 'Подписка на канал';
      default:
        return type;
    }
  }

  String _date(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

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
          Text(
            'Баланс',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
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
            style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

class _WalletData {
  const _WalletData({
    required this.balance,
    required this.packages,
    required this.transactions,
  });

  final StarsBalance balance;
  final List<StarPackage> packages;
  final List<StarTransaction> transactions;
}
