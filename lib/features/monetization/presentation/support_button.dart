import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';

/// Кнопка "Поддержать" для профиля канала / поста
class SupportButton extends StatelessWidget {
  const SupportButton({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.channelId,
    this.postId,
    this.channelName,
    this.compact = false,
  });

  final int recipientId;
  final String recipientName;
  final int? channelId;
  final int? postId;
  final String? channelName;
  final bool compact;

  Future<void> _openDonationScreen(BuildContext context) async {
    await context.push(
      DonateRoute.pathFor(
        recipientId: recipientId,
        recipientName: recipientName,
        channelId: channelId,
        postId: postId,
        channelName: channelName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return OutlinedButton.icon(
        onPressed: () => _openDonationScreen(context),
        icon: const Icon(Icons.favorite_border, size: 18),
        label: const Text('Поддержать'),
      );
    }

    return FilledButton.icon(
      onPressed: () => _openDonationScreen(context),
      icon: const Icon(Icons.favorite),
      label: const Text('Поддержать автора'),
    );
  }
}
