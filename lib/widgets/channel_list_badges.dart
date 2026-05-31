import 'package:flutter/material.dart';
import '../services/channel_service.dart';

/// Бейджи для карточки канала в списках (приватный, заявка, ожидание).
class ChannelListBadges extends StatelessWidget {
  const ChannelListBadges({
    super.key,
    required this.channel,
    this.spacing = 6,
  });

  final Channel channel;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (!channel.isPublic) {
      chips.add(_badge(
        context,
        label: 'Приватный',
        icon: Icons.lock_outline,
        color: Theme.of(context).colorScheme.secondaryContainer,
        onColor: Theme.of(context).colorScheme.onSecondaryContainer,
      ));
    }

    if (channel.isPending) {
      chips.add(_badge(
        context,
        label: 'Ожидает одобрения',
        icon: Icons.hourglass_top,
        color: Theme.of(context).colorScheme.tertiaryContainer,
        onColor: Theme.of(context).colorScheme.onTertiaryContainer,
      ));
    }

    final pendingRequests = channel.pendingJoinRequestsCount;
    if (pendingRequests != null && pendingRequests > 0) {
      chips.add(_badge(
        context,
        label: 'Заявок: $pendingRequests',
        icon: Icons.person_add_alt_1_outlined,
        color: Theme.of(context).colorScheme.errorContainer,
        onColor: Theme.of(context).colorScheme.onErrorContainer,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: spacing),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: chips,
      ),
    );
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required Color onColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: onColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
