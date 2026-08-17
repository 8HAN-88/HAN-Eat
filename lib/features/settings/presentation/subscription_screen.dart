import 'package:flutter/material.dart';

import '../../subscription/presentation/flex_subscription_screen.dart';

/// Классические тарифы сняты — экран ведёт на гибкую подписку.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key, this.initialProduct});

  final String? initialProduct;

  @override
  Widget build(BuildContext context) => const FlexSubscriptionScreen();
}
