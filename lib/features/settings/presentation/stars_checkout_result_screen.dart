import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/paid_features_service.dart';

/// Экран возврата после оплаты пакета Stars.
class StarsCheckoutSuccessScreen extends StatefulWidget {
  const StarsCheckoutSuccessScreen({super.key});

  @override
  State<StarsCheckoutSuccessScreen> createState() =>
      _StarsCheckoutSuccessScreenState();
}

class _StarsCheckoutSuccessScreenState
    extends State<StarsCheckoutSuccessScreen> {
  bool _loading = true;
  int? _balance;
  int _attempts = 0;
  static const _maxAttempts = 8;

  @override
  void initState() {
    super.initState();
    _pollBalance();
  }

  Future<void> _pollBalance() async {
    for (var i = 0; i < _maxAttempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      setState(() => _attempts = i + 1);
      try {
        final bal = await PaidFeaturesService.getBalance();
        if (!mounted) return;
        setState(() {
          _balance = bal.balance;
          _loading = false;
        });
        return;
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Покупка звёзд'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _loading
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_outline_rounded,
                size: 72,
                color: _loading ? scheme.secondary : scheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                _loading
                    ? 'Проверяем оплату…'
                    : _balance != null
                        ? 'Звёзды зачислены'
                        : 'Проверяем зачисление звёзд',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                _loading
                    ? 'Попытка $_attempts из $_maxAttempts'
                    : _balance != null
                        ? 'Текущий баланс: $_balance ★'
                        : 'Если баланс не обновился — откройте кошелёк и потяните вниз.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.go(StarsWalletRoute.path),
                child: const Text('Открыть кошелёк'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StarsCheckoutCancelScreen extends StatelessWidget {
  const StarsCheckoutCancelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Оплата отменена'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_outlined, size: 72, color: Colors.orange),
              const SizedBox(height: 20),
              Text(
                'Покупка звёзд отменена',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Платёж не был завершён. Баланс не изменился.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.go(StarsWalletRoute.path),
                child: const Text('Вернуться в кошелёк'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
