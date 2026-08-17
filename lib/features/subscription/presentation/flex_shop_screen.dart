import 'package:flutter/material.dart';

import 'flex_subscription_screen.dart';

/// Магазин функций встроен в «Моя подписка» — старый маршрут ведёт туда же.
class FlexShopScreen extends StatelessWidget {
  const FlexShopScreen({super.key});

  @override
  Widget build(BuildContext context) => const FlexSubscriptionScreen();
}
