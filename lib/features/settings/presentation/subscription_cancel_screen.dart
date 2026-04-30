import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Экран отмены оплаты подписки
class SubscriptionCancelScreen extends StatelessWidget {
  const SubscriptionCancelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Оплата отменена'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cancel_outlined,
                size: 80,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                'Оплата отменена',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Вы отменили процесс оплаты. Подписка не была оформлена.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  context.go('/subscription');
                },
                child: const Text('Вернуться к подписке'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  context.go('/');
                },
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

