import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/payment_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/telegram_ui.dart';

/// История оплат на экране гибкой подписки (раньше жила только в старом UI).
class FlexPaymentHistory extends StatefulWidget {
  const FlexPaymentHistory({super.key});

  @override
  State<FlexPaymentHistory> createState() => _FlexPaymentHistoryState();
}

class _FlexPaymentHistoryState extends State<FlexPaymentHistory> {
  List<PaymentHistoryItem> _payments = [];
  bool _loading = true;
  String? _error;

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
      final items = await PaymentService.getPaymentHistory();
      if (!mounted) return;
      setState(() {
        _payments = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(
          e,
          fallback: 'Не удалось загрузить историю оплат',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReceipt(PaymentHistoryItem payment) async {
    final scheme = Theme.of(context).colorScheme;
    try {
      var url = payment.receiptUrl;
      if (url == null || url.isEmpty) {
        url = await PaymentService.refreshReceiptUrl(payment.id);
      }
      if (url != null && url.isNotEmpty) {
        await PaymentService.openReceiptUrl(url);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Чек ещё формируется. Попробуйте через несколько минут.',
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_openReceipt(payment)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          backgroundColor: scheme.error,
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_openReceipt(payment)),
          ),
        ),
      );
    }
  }

  Future<void> _requestRefund(PaymentHistoryItem payment) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Запрос возврата'),
        content: Text(
          'Отправить запрос на возврат ${payment.amount.toStringAsFixed(0)} ₽ '
          'за «${_displayName(payment)}»? Поддержка обработает его в течение нескольких дней.',
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
    try {
      await PaymentService.requestRefund(subscriptionId: payment.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Запрос на возврат отправлен'),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TelegramSectionHeader(
          title: 'История оплат',
          padding: EdgeInsets.fromLTRB(2, 8, 2, 8),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          TelegramGroupedSurface(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          )
        else if (_payments.isEmpty)
          TelegramGroupedSurface(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Пока нет оплат. После оплаты по СБП записи появятся здесь.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Обновить'),
                  ),
                ],
              ),
            ),
          )
        else
          ..._payments.take(10).map(
                (p) => _FlexPaymentTile(
                  payment: p,
                  onOpenReceipt: () => _openReceipt(p),
                  onRequestRefund: () => _requestRefund(p),
                ),
              ),
      ],
    );
  }
}

int? _flexLevelFromAmount(double amount) {
  const base = 39;
  const step = 10;
  final raw = amount.round();
  final level = ((raw - base) ~/ step) + 1;
  if (level < 1 || level > 79) return null;
  if (base + (level - 1) * step != raw) return null;
  return level;
}

String _displayName(PaymentHistoryItem payment) {
  switch (payment.product) {
    case 'ai':
      return 'HanWe · уровень 9';
    case 'creator':
      return 'HanWe · уровень 16';
    case 'pro':
      return 'HanWe · уровень 18';
    case 'flex':
      final named = payment.productName.trim();
      if (named.contains('уровень')) return named;
      final level = _flexLevelFromAmount(payment.amount);
      if (level != null) return 'HanWe · уровень $level';
      return named.isNotEmpty ? named : 'HanWe';
    default:
      return payment.productName;
  }
}

class _FlexPaymentTile extends StatelessWidget {
  const _FlexPaymentTile({
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
    final hasGateway = (payment.paymentProvider == 'yookassa' ||
            payment.paymentProvider == 'tbank') &&
        payment.paymentId != null &&
        !payment.paymentId!.startsWith('trial-');

    return TelegramGroupedSurface(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                hasGateway
                    ? Icons.account_balance_wallet_outlined
                    : Icons.payment_outlined,
              ),
              title: Text(_displayName(payment)),
              subtitle: Text(
                [
                  if (date.isNotEmpty) '$date · ${payment.statusLabel}',
                  '${payment.amount.toStringAsFixed(0)} ${payment.currency == 'RUB' ? '₽' : payment.currency}',
                  if (refundLine.isNotEmpty) refundLine,
                ].join('\n'),
              ),
              isThreeLine: refundLine.isNotEmpty || date.isNotEmpty,
            ),
            if (hasGateway)
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
