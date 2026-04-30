import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../services/subscription_service.dart';
import '../../../../services/payment_service.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isLoading = false;
  bool _isLoadingPrices = false;
  bool _hasActiveSubscription = false;
  DateTime? _expiresAt;
  SubscriptionPricesResponse? _prices;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
    _loadPrices();
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      final status = await SubscriptionService.getSubscriptionStatus();
      if (mounted) {
        setState(() {
          _hasActiveSubscription = status.isPlus;
          _expiresAt = status.expiresAt;
        });
      }
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  Future<void> _loadPrices() async {
    setState(() => _isLoadingPrices = true);
    try {
      final prices = await PaymentService.getPrices();
      if (mounted) {
        setState(() {
          _prices = prices;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить цены: $e'),
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

  Future<void> _purchaseSubscription(String plan) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Создаем checkout session с URL для возврата в приложение
      final baseUrl = Uri.base.origin; // Получаем базовый URL приложения
      final checkout = await PaymentService.createCheckoutSession(
        plan: plan,
        successUrl: '$baseUrl/subscription/success?session_id={CHECKOUT_SESSION_ID}',
        cancelUrl: '$baseUrl/subscription/cancel',
      );

      // Открываем Stripe Checkout в браузере
      await PaymentService.openCheckout(checkout.url);

      if (mounted) {
        // Показываем диалог с инструкциями
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Завершение оплаты'),
            content: const Text(
              'Откройте браузер для завершения оплаты. '
              'После успешной оплаты вы будете перенаправлены обратно в приложение.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Проверяем статус подписки через несколько секунд
                  Future.delayed(const Duration(seconds: 5), () {
                    _loadSubscriptionStatus();
                  });
                },
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при создании платежа: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatPrice(double price, String currency) {
    final formatter = NumberFormat.currency(
      symbol: currency == 'USD' ? '\$' : '₽',
      decimalDigits: currency == 'RUB' ? 0 : 2, // Рубли без копеек
    );
    return formatter.format(price);
  }
  
  String _getPaymentMethodName() {
    if (_prices?.provider == 'yookassa') {
      return 'СБП, карты, электронные кошельки';
    } else if (_prices?.provider == 'stripe') {
      return 'Банковские карты';
    }
    return 'Банковские карты';
  }

  Future<void> _requestCancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить подписку?'),
        content: const Text(
          'Ваш запрос на отмену подписки будет отправлен в поддержку. '
          'Подписка останется активной до даты истечения после обработки запроса.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final response = await SubscriptionService.requestCancelSubscription();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
        // Переходим на экран поддержки
        context.push('/support');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подписка H.A.N. Plus')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Заголовок
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.workspace_premium,
                    size: 64,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'H.A.N. Plus',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Расширенные возможности для любителей кулинарии',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Преимущества
          Text(
            'Преимущества подписки',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _FeatureTile(
                  icon: Icons.block,
                  title: 'Без рекламы',
                  description: 'Наслаждайтесь приложением без отвлекающей рекламы',
                ),
                const Divider(height: 1),
                _FeatureTile(
                  icon: Icons.download,
                  title: 'Оффлайн режим',
                  description: 'Сохраняйте рецепты для просмотра без интернета',
                ),
                const Divider(height: 1),
                _FeatureTile(
                  icon: Icons.analytics,
                  title: 'Расширенный анализ питания',
                  description: 'Детальная статистика по калориям, БЖУ и витаминам',
                ),
                const Divider(height: 1),
                _FeatureTile(
                  icon: Icons.payments,
                  title: 'Выплаты авторам',
                  description: 'Поддерживайте создателей контента и получайте бонусы',
                ),
                const Divider(height: 1),
                _FeatureTile(
                  icon: Icons.star,
                  title: 'Приоритетная поддержка',
                  description: 'Быстрые ответы от команды поддержки',
                ),
                const Divider(height: 1),
                _FeatureTile(
                  icon: Icons.restaurant_menu,
                  title: 'Эксклюзивные рецепты',
                  description: 'Доступ к уникальным рецептам от шеф-поваров',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Тарифы
          Text(
            'Выберите план',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_isLoadingPrices)
            const Center(child: CircularProgressIndicator())
          else if (_prices != null) ...[
            _PricingCard(
              title: 'Месячный',
              price: _formatPrice(_prices!.monthly.price, _prices!.monthly.currency),
              period: 'в месяц',
              isLoading: _isLoading,
              onTap: () => _purchaseSubscription('monthly'),
            ),
            const SizedBox(height: 12),
            _PricingCard(
              title: 'Годовой',
              price: _formatPrice(_prices!.yearly.price, _prices!.yearly.currency),
              period: 'в год',
              savings: 'Экономия ${_formatPrice((_prices!.monthly.price * 12) - _prices!.yearly.price, _prices!.yearly.currency)}',
              isPopular: true,
              isLoading: _isLoading,
              onTap: () => _purchaseSubscription('yearly'),
            ),
          ] else ...[
            // Fallback цены (в рублях для России)
            _PricingCard(
              title: 'Месячный',
              price: '299 ₽',
              period: 'в месяц',
              isLoading: _isLoading,
              onTap: () => _purchaseSubscription('monthly'),
            ),
            const SizedBox(height: 12),
            _PricingCard(
              title: 'Годовой',
              price: '2499 ₽',
              period: 'в год',
              savings: 'Экономия 588 ₽',
              isPopular: true,
              isLoading: _isLoading,
              onTap: () => _purchaseSubscription('yearly'),
            ),
          ],
          // Информация о способе оплаты
          if (_prices != null && _prices!.provider == 'yookassa') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Оплата через СБП, банковские карты или электронные кошельки',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Статус подписки (если активна)
          if (_hasActiveSubscription) ...[
            Card(
              color: Colors.green.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Подписка активна',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    if (_expiresAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Действует до: ${_expiresAt!.day}.${_expiresAt!.month}.${_expiresAt!.year}',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _requestCancelSubscription,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Запросить отмену подписки'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Информация
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'О подписке',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Подписка автоматически продлевается\n'
                    '• Для отмены подписки обратитесь в поддержку\n'
                    '• Оплата производится через ${_getPaymentMethodName()}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => context.push('/support'),
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Связаться с поддержкой'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(description, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String? savings;
  final bool isPopular;
  final bool isLoading;
  final VoidCallback onTap;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    this.savings,
    this.isPopular = false,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isPopular ? 4 : 1,
      color: isPopular
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        child: Opacity(
          opacity: isLoading ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ПОПУЛЯРНЫЙ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (isPopular) const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      period,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (savings != null) ...[
                const SizedBox(height: 8),
                Text(
                  savings!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

