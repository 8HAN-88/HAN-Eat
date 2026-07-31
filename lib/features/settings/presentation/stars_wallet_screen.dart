import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/config/stars_checkout_urls.dart';
import '../../../services/paid_features_service.dart';
import '../../../services/payment_service.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/telegram_ui.dart';
import 'widgets/stars_wallet_widgets.dart';

class StarsWalletScreen extends StatefulWidget {
  const StarsWalletScreen({super.key});

  @override
  State<StarsWalletScreen> createState() => _StarsWalletScreenState();
}

class _StarsWalletScreenState extends State<StarsWalletScreen>
    with WidgetsBindingObserver {
  late Future<_WalletData> _future;
  bool _checkoutLoading = false;
  bool _awaitingCheckoutReturn = false;
  WalletFilter _filter = WalletFilter.all;
  WalletStatsPeriod _statsPeriod = WalletStatsPeriod.days30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingCheckoutReturn) {
      _awaitingCheckoutReturn = false;
      _refresh();
    }
  }

  Future<_WalletData> _load() async {
    final results = await Future.wait([
      PaidFeaturesService.getBalance(),
      PaidFeaturesService.getStarPackages(),
      PaidFeaturesService.getTransactions(limit: 120),
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

  Future<void> _refreshAndWait() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _buyPackage(StarPackage package) async {
    if (_checkoutLoading) return;
    setState(() => _checkoutLoading = true);
    try {
      final checkout = await PaidFeaturesService.createStarsCheckout(
        package.id,
        successUrl: StarsCheckoutUrls.successUrl(),
        cancelUrl: StarsCheckoutUrls.cancelUrl(),
      );
      _awaitingCheckoutReturn = true;
      await PaymentService.openCheckout(checkout.url);
    } catch (e) {
      _awaitingCheckoutReturn = false;
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
            final filteredTransactions = data.transactions
                .where((tx) => _filter.matches(tx.type, tx.amount))
                .toList();
            return RefreshIndicator(
              onRefresh: _refreshAndWait,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  StarsBalanceCard(balance: data.balance),
                  const SizedBox(height: 12),
                  CreatorDashboardCard(
                    balance: data.balance,
                    transactions: data.transactions,
                    period: _statsPeriod,
                    onPeriodChanged: (next) =>
                        setState(() => _statsPeriod = next),
                  ),
                  const SizedBox(height: 10),
                  TelegramGroupedSurface(
                    margin: EdgeInsets.zero,
                    child: TelegramActionRow(
                      icon: Icons.insights_outlined,
                      title: 'Доходы автора',
                      subtitle: 'Периоды, источники и экспорт CSV',
                      onTap: () => context.push(CreatorRevenueRoute.path),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TelegramGroupedSurface(
                    margin: EdgeInsets.zero,
                    child: TelegramActionRow(
                      icon: Icons.card_giftcard_rounded,
                      title: 'Мои подарки',
                      subtitle: 'Оставить в профиле или конвертировать в ★',
                      onTap: () => context.push(StarGiftsInventoryRoute.path),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const TelegramSectionHeader(
                    title: 'Купить звёзды',
                    padding: EdgeInsets.fromLTRB(2, 6, 2, 8),
                  ),
                  for (final package in data.packages)
                    TelegramGroupedSurface(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: TelegramActionRow(
                        icon: Icons.stars_rounded,
                        title: package.title,
                        subtitle: '${package.stars} ★ за ${package.priceRub} ₽',
                        iconColor: scheme.secondary,
                        trailing: FilledButton(
                          onPressed: _checkoutLoading
                              ? null
                              : () => _buyPackage(package),
                          child: const Text('Купить'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const TelegramSectionHeader(
                    title: 'История',
                    padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in WalletFilter.values) ...[
                          FilterChip(
                            selected: _filter == filter,
                            label: Text(filter.label),
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (filteredTransactions.isEmpty)
                    TelegramGroupedSurface(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Операций пока нет',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    for (final tx in filteredTransactions)
                      TelegramGroupedSurface(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: TelegramActionRow(
                          icon: tx.amount >= 0
                              ? Icons.add_circle_outline_rounded
                              : Icons.remove_circle_outline_rounded,
                          title: _txTitle(tx.type),
                          subtitle: _date(tx.createdAt),
                          iconColor: tx.amount >= 0 ? scheme.primary : null,
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
      case 'admin_adjust':
        return 'Начисление звёзд';
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
      case 'channel_subscription_received':
        return 'Подписка на ваш канал';
      case 'gift':
        return 'Подарок отправлен';
      case 'gift_received':
        return 'Подарок получен';
      case 'gift_converted':
        return 'Подарок → ★';
      case 'giveaway_escrow':
        return 'Розыгрыш (эскроу)';
      case 'giveaway_prize':
        return 'Приз розыгрыша';
      case 'giveaway_refund':
        return 'Возврат розыгрыша';
      case 'invoice_payment':
        return 'Оплата счёта бота';
      case 'invoice_received':
        return 'Счёт бота оплачен';
      case 'paid_media_purchase':
        return 'Платное медиа';
      case 'paid_media_sale':
        return 'Продажа медиа';
      case 'paid_message':
        return 'Плата за сообщение';
      case 'paid_message_received':
        return 'Оплата за сообщение вам';
      case 'paid_reaction':
        return 'Платная реакция';
      case 'paid_reaction_received':
        return 'Платная реакция получена';
      case 'payout':
        return 'Выплата';
      default:
        return type;
    }
  }

  String _date(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
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
