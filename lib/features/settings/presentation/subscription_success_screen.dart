import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/ai_scan_gate.dart';
import '../../../services/subscription_service.dart';
import '../application/subscription_status_provider.dart';

/// Экран успешной оплаты подписки
class SubscriptionSuccessScreen extends ConsumerStatefulWidget {
  final String? sessionId;

  const SubscriptionSuccessScreen({
    super.key,
    this.sessionId,
  });

  @override
  ConsumerState<SubscriptionSuccessScreen> createState() =>
      _SubscriptionSuccessScreenState();
}

class _SubscriptionSuccessScreenState
    extends ConsumerState<SubscriptionSuccessScreen> {
  bool _isLoading = true;
  bool _subscriptionActive = false;
  int _attemptsDone = 0;
  static const int _maxAttempts = 10;
  static const Duration _delayBetweenAttempts = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    setState(() {
      _isLoading = true;
    });

    refreshSubscriptionStatus(ref);
    await Future<void>.delayed(const Duration(seconds: 1));

    for (var i = 0; i < _maxAttempts; i++) {
      if (i > 0) {
        await Future<void>.delayed(_delayBetweenAttempts);
      }
      if (!mounted) return;

      try {
        final status = await SubscriptionService.getSubscriptionStatus();
        if (mounted) {
          setState(() {
            _attemptsDone = i + 1;
          });
        }
        final paid = status.hasAnyPaid;
        if (paid) {
          refreshSubscriptionStatus(ref);
          AiScanGate.invalidateCache();
          if (mounted) {
            setState(() {
              _subscriptionActive = true;
              _isLoading = false;
            });
          }
          return;
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _attemptsDone = i + 1;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _subscriptionActive = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Оплата подписки'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text('Проверка статуса подписки…'),
                const SizedBox(height: 8),
                Text(
                  'Попытка $_attemptsDone из $_maxAttempts (webhook может задержаться)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (_subscriptionActive) ...[
                Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Colors.green,
                ),
                const SizedBox(height: 24),
                Text(
                  'Подписка активирована!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Спасибо за подписку! '
                  'Теперь вам доступны возможности выбранного тарифа.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    context.go(SubscriptionRoute.path);
                  },
                  child: const Text('Вернуться к подписке'),
                ),
              ] else ...[
                Icon(
                  Icons.hourglass_empty,
                  size: 80,
                  color: Colors.orange,
                ),
                const SizedBox(height: 24),
                Text(
                  'Обработка платежа',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ваш платеж обрабатывается. Подписка будет активирована в течение нескольких минут. '
                  'Если подписка не активировалась, обратитесь в поддержку.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _checkSubscriptionStatus,
                  child: const Text('Проверить снова'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    context.go(SubscriptionRoute.path);
                  },
                  child: const Text('Вернуться к подписке'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
