// Дополнительные компоненты для вкладок канала
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../widgets/highlighted_text.dart';

/// Пустое состояние вкладки (NestedScrollView + TabBarView): без bottom overflow.
class ChannelTabEmptyPlaceholder extends StatelessWidget {
  const ChannelTabEmptyPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 64, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Делегат для закрепления TabBar в Sliver
class SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: overlapsContent ? 1 : 0,
      shadowColor: Colors.black26,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}

// Вкладка "О канале"
class ChannelAboutTab extends StatelessWidget {
  final ChannelDetail channel;

  /// Если описание уже показано на экране профиля (карточка как в Telegram).
  final bool omitDescription;

  const ChannelAboutTab({
    super.key,
    required this.channel,
    this.omitDescription = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Описание
          if (!omitDescription &&
              channel.description != null &&
              channel.description!.isNotEmpty) ...[
            Text(
              'Описание',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            HighlightedText(
              text: channel.description!,
              style: Theme.of(context).textTheme.bodyLarge ??
                  const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
          ],
          // Правила канала
          if (channel.rules != null && channel.rules!.isNotEmpty) ...[
            Text(
              'Правила канала',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: HighlightedText(
                text: channel.rules!,
                style: Theme.of(context).textTheme.bodyMedium ??
                    const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Теги
          if (channel.tags != null && channel.tags!.isNotEmpty) ...[
            Text(
              'Теги',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: channel.tags!.map((tag) {
                return Chip(
                  label: HighlightedText(
                    text: '#$tag',
                    style: Theme.of(context).textTheme.labelLarge ??
                        const TextStyle(fontSize: 14),
                  ),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
          // Статистика
          Text(
            'Статистика',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                icon: Icons.people,
                label: 'Подписчики',
                value: channel.membersCount.toString(),
                onTap: () => context.push(
                  ChannelDetailRoute.subscribers(
                    channel.id,
                    channelName: channel.name,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              _StatItem(
                icon: Icons.article,
                label: 'Посты',
                value: channel.postsCount.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: child,
      ),
    );
  }
}
