import 'package:flutter/material.dart';
import 'feed_filter_menu.dart';

/// Вкладки ленты: стандартный [TabBar] с плавным индикатором (как в «Чатах»).
class FeedSectionTabs extends StatelessWidget {
  const FeedSectionTabs({
    super.key,
    required this.controller,
    required this.subsFeedType,
    required this.recFeedType,
    required this.reelsFollowingOnly,
    required this.onSubsFilterChanged,
    required this.onRecFilterChanged,
    required this.onReelsFilterChanged,
  });

  final TabController controller;
  final String subsFeedType;
  final String recFeedType;
  final bool reelsFollowingOnly;
  final ValueChanged<String> onSubsFilterChanged;
  final ValueChanged<String> onRecFilterChanged;
  final ValueChanged<bool> onReelsFilterChanged;

  static const _labels = ['Подписки', 'Рекомендации', 'Рилсы'];

  List<PopupMenuEntry<String>> _filterItems(int index) {
    if (index == 2) {
      return reelsSourceFilterMenuItems(
        followingOnly: reelsFollowingOnly,
      );
    }
    return feedContentFilterMenuItems(
      index == 0 ? subsFeedType : recFeedType,
    );
  }

  void _onFilterSelected(int index, String value) {
    switch (index) {
      case 0:
        onSubsFilterChanged(value);
      case 1:
        onRecFilterChanged(value);
      case 2:
        onReelsFilterChanged(value == 'following');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return TabBar(
          controller: controller,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          splashFactory: InkRipple.splashFactory,
          labelColor: scheme.onSurface,
          unselectedLabelColor: scheme.onSurfaceVariant.withValues(alpha: 0.82),
          labelStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            for (var i = 0; i < _labels.length; i++)
              Tab(
                height: 46,
                child: _TabLabel(
                  label: _labels[i],
                  filterArrow: controller.index == i
                      ? _FilterArrow(
                          onSelected: (value) => _onFilterSelected(i, value),
                          items: _filterItems(i),
                        )
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    this.filterArrow,
  });

  final String label;
  final Widget? filterArrow;

  static const _arrowSlotWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _arrowSlotWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: filterArrow,
          ),
        ),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FilterArrow extends StatelessWidget {
  const _FilterArrow({
    required this.onSelected,
    required this.items,
  });

  final ValueChanged<String> onSelected;
  final List<PopupMenuEntry<String>> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: 'Фильтр',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      offset: const Offset(-4, 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: scheme.primary.withValues(alpha: 0.9),
      ),
    );
  }
}
