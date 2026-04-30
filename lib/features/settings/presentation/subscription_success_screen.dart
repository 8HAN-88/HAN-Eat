import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../services/subscription_service.dart';

/// Экран успешной оплаты подписки
class SubscriptionSuccessScreen extends StatefulWidget {
  final String? sessionId;

  const SubscriptionSuccessScreen({
    super.key,
    this.sessionId,
  });

  @override
  State<SubscriptionSuccessScreen> createState() => _SubscriptionSuccessScreenState();
}

class _SubscriptionSuccessScreenState extends State<SubscriptionSuccessScreen> {
  bool _isLoading = true;
  bool _subscriptionActive = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    // Ждем немного, чтобы webhook успел обработать платеж
    await Future.delayed(const Duration(seconds: 2));

    try {
      final status = await SubscriptionService.getSubscriptionStatus();
      if (mounted) {
        setState(() {
          _subscriptionActive = status.isPlus;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
                const Text('Проверка статуса подписки...'),
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
                  'Спасибо за подписку на H.A.N. Plus! '
                  'Теперь вы можете пользоваться всеми преимуществами подписки.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () {
                    context.go('/subscription');
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
                  onPressed: () {
                    _checkSubscriptionStatus();
                  },
                  child: const Text('Проверить снова'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    context.go('/subscription');
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

