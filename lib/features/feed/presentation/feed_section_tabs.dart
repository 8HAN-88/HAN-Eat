import 'package:flutter/material.dart';

import '../../../models/post_types.dart';
import '../../../core/haptics/app_haptics.dart';
import 'feed_filter_menu.dart';

/// Вкладки ленты: стандартный [TabBar] с плавным индикатором (как в «Чатах»).
class FeedSectionTabs extends StatelessWidget {
  const FeedSectionTabs({
    super.key,
    required this.controller,
    required this.subsFeedType,
    required this.subsSortMode,
    required this.recFeedType,
    required this.recSortMode,
    required this.reelsFollowingOnly,
    required this.onSubsFilterChanged,
    required this.onSubsSortChanged,
    required this.onRecFilterChanged,
    required this.onRecSortChanged,
    required this.onReelsFilterChanged,
  });

  final TabController controller;
  final String subsFeedType;
  final FeedSortMode subsSortMode;
  final String recFeedType;
  final FeedSortMode recSortMode;
  final bool reelsFollowingOnly;
  final ValueChanged<String> onSubsFilterChanged;
  final ValueChanged<FeedSortMode> onSubsSortChanged;
  final ValueChanged<String> onRecFilterChanged;
  final ValueChanged<FeedSortMode> onRecSortChanged;
  final ValueChanged<bool> onReelsFilterChanged;

  static const labels = ['Подписки', 'Рекомендации', 'Рилсы'];

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

  List<PopupMenuEntry<String>> _feedTabFilterItems(int index) {
    return feedTabFilterMenuItems(
      currentType: index == 0 ? subsFeedType : recFeedType,
      currentSort: index == 0 ? subsSortMode : recSortMode,
    );
  }

  List<PopupMenuEntry<String>> _itemsForTab(int index) {
    if (index == 2) {
      return reelsSourceFilterMenuItems(
        followingOnly: reelsFollowingOnly,
      );
    }
    if (index == 0 || index == 1) return _feedTabFilterItems(index);
    return _filterItems(index);
  }

  void _onFilterSelected(int index, String value) {
    AppHaptics.selection();
    if ((index == 0 || index == 1) && value.startsWith('sort:')) {
      final sort = FeedSortMode.fromString(value.substring(5));
      if (sort == null) return;
      if (index == 0) {
        onSubsSortChanged(sort);
      } else {
        onRecSortChanged(sort);
      }
      return;
    }
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
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          splashFactory: InkRipple.splashFactory,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: scheme.primary, width: 3),
            borderRadius: BorderRadius.circular(999),
          ),
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurfaceVariant.withValues(alpha: 0.82),
          labelStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            fontSize: 14,
          ),
          unselectedLabelStyle: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: [
            for (var i = 0; i < labels.length; i++)
              Tab(
                height: 40,
                child: _TabLabel(
                  label: labels[i],
                  filterArrow: controller.index == i
                      ? _FilterArrow(
                          onSelected: (value) => _onFilterSelected(i, value),
                          items: _itemsForTab(i),
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
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
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
