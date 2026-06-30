import 'package:flutter/material.dart';

/// Кнопка подписки на платный канал
class ChannelSubscriptionButton extends StatelessWidget {
  const ChannelSubscriptionButton({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.monthlyPriceStars,
    this.isSubscribed = false,
    this.onSubscribe,
  });

  final int channelId;
  final String channelName;
  final int monthlyPriceStars;
  final bool isSubscribed;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    if (isSubscribed) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle),
        label: const Text('Вы подписаны'),
      );
    }

    return FilledButton.icon(
      onPressed: onSubscribe,
      icon: const Icon(Icons.star),
      label: Text('Подписаться за $monthlyPriceStars ★/мес'),
    );
  }
}
