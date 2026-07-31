import 'package:flutter/material.dart';

/// Кнопка подписки / управления платной подпиской на канал (Telegram Stars).
class ChannelSubscriptionButton extends StatelessWidget {
  const ChannelSubscriptionButton({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.monthlyPriceStars,
    this.isSubscribed = false,
    this.onSubscribe,
    this.onManage,
  });

  final int channelId;
  final String channelName;
  final int monthlyPriceStars;
  final bool isSubscribed;
  final VoidCallback? onSubscribe;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    if (isSubscribed) {
      return OutlinedButton.icon(
        onPressed: onManage,
        icon: const Icon(Icons.workspace_premium_rounded),
        label: const Text('Подписка'),
      );
    }

    return FilledButton.icon(
      onPressed: onSubscribe,
      icon: const Icon(Icons.star),
      label: Text('Подписаться за $monthlyPriceStars ★/мес'),
    );
  }
}
