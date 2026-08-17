import 'package:flutter/material.dart';

import 'flex_subscription_screen.dart';

/// Конструктор встроен в «Моя подписка» — старый маршрут ведёт туда же.
class FlexConstructorScreen extends StatelessWidget {
  const FlexConstructorScreen({super.key});

  @override
  Widget build(BuildContext context) => const FlexSubscriptionScreen();
}
