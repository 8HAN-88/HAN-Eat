import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../services/auth_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';

/// Pay a bot Stars invoice (Telegram Bot Payments–like).
class StarInvoicePayScreen extends StatefulWidget {
  const StarInvoicePayScreen({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  State<StarInvoicePayScreen> createState() => _StarInvoicePayScreenState();
}

class _StarInvoicePayScreenState extends State<StarInvoicePayScreen> {
  StarInvoice? _invoice;
  Object? _error;
  bool _loading = true;
  bool _paying = false;
  bool _cancelling = false;
  bool _refunding = false;

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
      final invoice = await PaidFeaturesService.getInvoice(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pay() async {
    final invoice = _invoice;
    if (invoice == null || _paying || !invoice.isPayable) return;
    final ok = await confirmStarsSpend(
      context,
      title: invoice.title,
      body: invoice.description?.trim().isNotEmpty == true
          ? invoice.description!.trim()
          : 'Оплата счёта бота звёздами.',
      amountStars: invoice.amountStars,
      confirmLabel: 'Оплатить',
    );
    if (!ok || !mounted) return;
    setState(() => _paying = true);
    try {
      final result = await PaidFeaturesService.payInvoice(invoice.id);
      if (!mounted) return;
      setState(() {
        _invoice = result.invoice;
        _paying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Оплачено · баланс ${result.balance} ★')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      await showStarsRequiredSnack(context, e);
    }
  }

  Future<void> _cancel() async {
    final invoice = _invoice;
    final me = AuthService.instance.currentUser?.id;
    if (invoice == null ||
        _cancelling ||
        !invoice.isPayable ||
        me == null ||
        me != invoice.creatorUserId) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить счёт'),
        content: const Text('Счёт больше нельзя будет оплатить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final next = await PaidFeaturesService.cancelInvoice(invoice.id);
      if (!mounted) return;
      setState(() {
        _invoice = next;
        _cancelling = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Счёт отменён')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_cancel()),
          ),
        ),
      );
    }
  }

  Future<void> _refund() async {
    final invoice = _invoice;
    final me = AuthService.instance.currentUser?.id;
    if (invoice == null ||
        _refunding ||
        invoice.status != 'paid' ||
        me == null ||
        me != invoice.creatorUserId) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вернуть оплату'),
        content: Text(
          'Плательщику будет возвращено ${invoice.amountStars} ★ с вашего баланса.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Вернуть ${invoice.amountStars} ★'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _refunding = true);
    try {
      final result = await PaidFeaturesService.refundInvoice(invoice.id);
      if (!mounted) return;
      setState(() {
        _invoice = result.invoice;
        _refunding = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Возврат выполнен · баланс ${result.balance} ★')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _refunding = false);
      await showStarsRequiredSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final invoice = _invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('Счёт Stars')),
      body: AppGradientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(userVisibleError(_error!), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        invoice!.title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        invoice.botName ??
                            (invoice.botUsername != null
                                ? '@${invoice.botUsername}'
                                : 'Бот'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      if (invoice.description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(invoice.description!.trim()),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${invoice.amountStars} ★',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.secondary,
                              ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Статус: ${invoice.status}'
                        '${invoice.expiresAt != null ? ' · до ${DateFormat('d MMM, HH:mm', 'ru').format(invoice.expiresAt!.toLocal())}' : ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      if (invoice.isPayable) ...[
                        FilledButton(
                          onPressed: _paying ? null : _pay,
                          child: _paying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text('Оплатить ${invoice.amountStars} ★'),
                        ),
                        if (AuthService.instance.currentUser?.id ==
                            invoice.creatorUserId) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _cancelling ? null : _cancel,
                            child: _cancelling
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Отменить счёт'),
                          ),
                        ],
                      ] else ...[
                        Text(
                          invoice.status == 'paid'
                              ? 'Счёт уже оплачен'
                              : invoice.status == 'cancelled'
                                  ? 'Счёт отменён'
                                  : invoice.status == 'refunded'
                                      ? 'Оплата возвращена'
                                      : 'Счёт недоступен для оплаты',
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => context.go('/paid/wallet'),
                          child: const Text('К кошельку Stars'),
                        ),
                        if (invoice.status == 'paid' &&
                            AuthService.instance.currentUser?.id ==
                                invoice.creatorUserId) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _refunding ? null : _refund,
                            child: _refunding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Вернуть оплату · ${invoice.amountStars} ★',
                                  ),
                          ),
                        ],
                      ],
                    ],
                  ),
      ),
    );
  }
}
