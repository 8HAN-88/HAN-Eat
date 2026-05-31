import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../app/app_router.dart';
import '../../../core/config/subscription_checkout_urls.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../../services/subscription_service.dart';
import '../../../../services/payment_service.dart';
import '../../../../services/product_analytics.dart';
import '../application/subscription_status_provider.dart';
import '../../subscription/subscription_copy.dart';
import '../../subscription/presentation/widgets/subscription_visuals.dart';
import '../../support/presentation/widgets/subscription_cancel_survey_sheet.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, this.initialProduct});

  /// Предвыбор тарифа: ai | creator | pro
  final String? initialProduct;

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  bool _isLoadingPrices = false;
  bool _loadingPayments = false;
  SubscriptionPricesResponse? _prices;
  List<PaymentHistoryItem> _payments = [];
  late String _selectedProduct;

  static const _tierOrder = ['ai', 'creator', 'pro'];

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct ?? 'pro';
    if (!_tierOrder.contains(_selectedProduct)) {
      _selectedProduct = 'pro';
    }
    WidgetsBinding.instance.addObserver(this);
    _loadPrices();
    _loadPaymentHistory();
    ProductAnalytics.logEvent(
      eventType: 'subscription_paywall_view',
      metadata: {'initial_product': _selectedProduct},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshSubscriptionStatus(ref);
    }
  }

  Future<void> _loadPaymentHistory() async {
    setState(() => _loadingPayments = true);
    try {
      final items = await PaymentService.getPaymentHistory();
      if (mounted) setState(() => _payments = items);
    } catch (_) {
      // история опциональна
    } finally {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  Future<void> _openReceipt(PaymentHistoryItem payment) async {
    try {
      var url = payment.receiptUrl;
      if (url == null || url.isEmpty) {
        url = await PaymentService.refreshReceiptUrl(payment.id);
      }
      if (url != null && url.isNotEmpty) {
        await PaymentService.openReceiptUrl(url);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чек ещё формируется. Попробуйте через несколько минут.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _requestRefund(PaymentHistoryItem payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Запрос возврата'),
        content: Text(
          'Отправить запрос на возврат ${payment.amount.toStringAsFixed(0)} ₽ '
          'за «${payment.productName}»? Поддержка обработает его в течение нескольких дней.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await PaymentService.requestRefund(subscriptionId: payment.id);
      await _loadPaymentHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запрос на возврат отправлен'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPrices() async {
    setState(() => _isLoadingPrices = true);
    try {
      final prices = await PaymentService.getPrices();
      if (mounted) {
        setState(() => _prices = prices);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось загрузить цены'),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingPrices = false);
      }
    }
  }

  bool _canStartTrial(SubscriptionStatusResponse? status) {
    if (status == null || status.hasAnyPaid) return false;
    if (_selectedProduct == 'creator') return false;
    return status.trialEligibleFor(_selectedProduct);
  }

  Future<void> _startTrial() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await SubscriptionService.startTrial(product: _selectedProduct);
      ProductAnalytics.logEvent(
        eventType: 'subscription_trial_started',
        metadata: {'product': _selectedProduct},
      );
      refreshSubscriptionStatus(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пробный период активирован'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _purchaseSelected() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      ProductAnalytics.logEvent(
        eventType: 'subscription_checkout_start',
        metadata: {'product': _selectedProduct, 'provider': 'sbp'},
      );
      final checkout = await PaymentService.createCheckoutSession(
        plan: 'monthly',
        product: _selectedProduct,
        successUrl: SubscriptionCheckoutUrls.successUrl(),
        cancelUrl: SubscriptionCheckoutUrls.cancelUrl(),
      );
      await PaymentService.openCheckout(checkout.url);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Завершение оплаты'),
          content: const Text(
            'Откройте браузер для завершения оплаты. '
            'После успешной оплаты вернитесь в приложение — статус обновится автоматически.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Future<void>.delayed(const Duration(seconds: 5), () {
                  if (mounted) refreshSubscriptionStatus(ref);
                });
              },
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось создать платёж'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatPrice(double price, String currency) {
    return NumberFormat.currency(
      symbol: currency == 'USD' ? '\$' : '₽',
      decimalDigits: currency == 'RUB' ? 0 : 2,
    ).format(price);
  }

  List<String> _tierBenefits(String id) {
    final fromApi = _prices?.tier(id)?.benefits;
    return SubscriptionCopy.normalizeBenefits(id, fromApi ?? []);
  }

  double _fallbackPrice(String id) {
    switch (id) {
      case 'ai':
        return 199;
      case 'creator':
        return 499;
      case 'pro':
        return 649;
      default:
        return 199;
    }
  }

  String _checkoutButtonLabel(SubscriptionStatusResponse? status, bool hasPaid) {
    if (hasPaid && status != null) {
      final opt = status.upgradeOptions
          .where((o) => o.product == _selectedProduct)
          .firstOrNull;
      if (opt != null) {
        if (opt.isUpgrade && opt.amountDue > 0) {
          return 'Улучшить за ${opt.amountDue.toStringAsFixed(0)} ₽';
        }
        return 'Улучшить тариф';
      }
    }
    if (_prices?.provider == 'sbp') {
      return 'Оплатить по СБП';
    }
    return 'Продолжить';
  }

  String _priceLabel(String id) {
    final status = ref.read(subscriptionStatusProvider).asData?.value;
    final upgrade = status?.upgradeOptions.where((o) => o.product == id).firstOrNull;
    if (upgrade != null && upgrade.isUpgrade && upgrade.amountDue > 0) {
      return '${_formatPrice(upgrade.amountDue, 'RUB')} к оплате';
    }
    final tier = _prices?.tier(id);
    if (tier != null) {
      return '${_formatPrice(tier.monthly.price, tier.monthly.currency)}/мес';
    }
    return '${_formatPrice(_fallbackPrice(id), 'RUB')}/мес';
  }

  bool _tierOwned(String id, SubscriptionStatusResponse? status) {
    if (status == null || !status.isActive) return false;
    final t = status.subscriptionType;
    if (t == 'pro') return true;
    if (t == id) return true;
    return false;
  }

  Future<void> _requestCancelSubscription() async {
    setState(() => _isLoading = true);
    try {
      final ok = await runSubscriptionCancelFlow(context);
      if (!mounted || !ok) return;
      context.push(SupportContactRoute.path);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(subscriptionStatusProvider);
    final status = statusAsync.asData?.value;
    final hasPaid = status?.hasAnyPaid ?? false;
    final expiresAt = status?.expiresAt;
    final trialDays = _prices?.trialDays;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(SubscriptionCopy.screenTitle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + floatingBottomPadding(context),
        ),
        children: [
          SubscriptionHero(trialDays: trialDays),
          const SizedBox(height: 20),
          if (status != null && status.upgradeOptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...status.upgradeOptions.map((opt) {
              return Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                child: ListTile(
                  leading: Icon(
                    Icons.upgrade,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text('Улучшить до ${opt.name}'),
                  subtitle: Text(
                    [
                      if (opt.reason != null) opt.reason!,
                      if (opt.isUpgrade && opt.creditRub > 0)
                        'К оплате: ${opt.amountDue.toStringAsFixed(0)} ₽ '
                        '(учтено ${opt.creditRub.toStringAsFixed(0)} ₽ за ${opt.remainingDays} дн.)'
                      else
                        '${opt.monthlyPrice.toStringAsFixed(0)} ₽/мес · новый период 30 дней',
                    ].join('\n'),
                  ),
                  isThreeLine: opt.reason != null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _selectedProduct = opt.product),
                ),
              );
            }),
          ],
          const SizedBox(height: 20),
          if (_isLoadingPrices)
            const Center(child: CircularProgressIndicator())
          else
            ..._tierOrder.map((id) {
              final selected = _selectedProduct == id;
              final owned = _tierOwned(id, status);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SubscriptionTierCard(
                  tierId: id,
                  title: SubscriptionCopy.tierTitle(id),
                  subtitle: SubscriptionCopy.tierSubtitle(id),
                  priceLabel: _priceLabel(id),
                  benefits: _tierBenefits(id),
                  isSelected: selected,
                  isRecommended: id == 'pro',
                  isOwned: owned,
                  trialEligible: _prices?.tier(id)?.trialEligible ?? (id != 'creator'),
                  onTap: owned
                      ? null
                      : () => setState(() => _selectedProduct = id),
                ),
              );
            }),
          if (hasPaid) ...[
            const SizedBox(height: 8),
            Card(
              color: Colors.green.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Активен: ${SubscriptionCopy.tierTitle(status!.subscriptionType)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (status.inGracePeriod) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Льготный период: доступ сохранён на несколько дней после окончания оплаты',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    if (expiresAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'До ${expiresAt.day}.${expiresAt.month}.${expiresAt.year}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                    if (status.platform != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Платформа: ${status.platform}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _requestCancelSubscription,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Запросить отмену'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (status?.inGracePeriod == true) ...[
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_bottom,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Льготный период: продлите подписку, чтобы не потерять доступ.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_canStartTrial(status)) ...[
            OutlinedButton(
              onPressed: _isLoading ? null : _startTrial,
              child: Text(
                'Попробовать ${SubscriptionCopy.tierTitle(_selectedProduct)} бесплатно',
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: subscriptionBrandGradientDecoration(
                radius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_isLoading || _tierOwned(_selectedProduct, status))
                      ? null
                      : _purchaseSelected,
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _checkoutButtonLabel(status, hasPaid),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Позже'),
          ),
          const SizedBox(height: 24),
          Text(
            'История оплат',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          if (_loadingPayments)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_payments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Пока нет оплат. После оплаты по СБП записи появятся здесь.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            ..._payments.take(10).map((p) => _PaymentHistoryTile(
                  payment: p,
                  onOpenReceipt: () => _openReceipt(p),
                  onRequestRefund: () => _requestRefund(p),
                )),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => context.push(SupportContactRoute.path),
            icon: const Icon(Icons.support_agent),
            label: const Text('Поддержка'),
          ),
        ],
      ),
    );
  }
}

class _PaymentHistoryTile extends StatelessWidget {
  const _PaymentHistoryTile({
    required this.payment,
    required this.onOpenReceipt,
    required this.onRequestRefund,
  });

  final PaymentHistoryItem payment;
  final VoidCallback onOpenReceipt;
  final VoidCallback onRequestRefund;

  @override
  Widget build(BuildContext context) {
    final date = payment.createdAt != null
        ? DateFormat('d MMM yyyy', 'ru').format(payment.createdAt!)
        : '';
    final refundLine = payment.refundStatusLabel;
    final hasYookassa = payment.paymentProvider == 'yookassa' &&
        payment.paymentId != null &&
        !payment.paymentId!.startsWith('trial-');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                hasYookassa
                    ? Icons.account_balance_wallet_outlined
                    : Icons.payment_outlined,
              ),
              title: Text(payment.productName),
              subtitle: Text(
                [
                  if (date.isNotEmpty) '$date · ${payment.statusLabel}',
                  '${payment.amount.toStringAsFixed(0)} ${payment.currency == 'RUB' ? '₽' : payment.currency}',
                  if (refundLine.isNotEmpty) refundLine,
                ].join('\n'),
              ),
              isThreeLine: refundLine.isNotEmpty || date.isNotEmpty,
            ),
            if (hasYookassa)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onOpenReceipt,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Чек'),
                  ),
                  if (payment.canRequestRefund)
                    TextButton.icon(
                      onPressed: onRequestRefund,
                      icon: const Icon(Icons.undo_outlined, size: 18),
                      label: const Text('Возврат'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
