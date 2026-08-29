import 'package:flutter/material.dart';

import '../../../models/post_types.dart';
import '../../../core/haptics/app_haptics.dart';
import '../application/feed_tab_layout.dart';
import 'feed_filter_menu.dart';

/// Вкладки ленты: стандартный [TabBar] с плавным индикатором (как в «Чатах»).
class FeedSectionTabs extends StatelessWidget {
  const FeedSectionTabs({
    super.key,
    required this.controller,
    required this.homeFeedType,
    required this.homeSortMode,
    required this.homeFollowingOnly,
    required this.reelsFollowingOnly,
    required this.onHomeFilterChanged,
    required this.onHomeSortChanged,
    required this.onHomeFollowingChanged,
    required this.onReelsFilterChanged,
  });

  final TabController controller;
  final String homeFeedType;
  final FeedSortMode homeSortMode;
  final bool homeFollowingOnly;
  final bool reelsFollowingOnly;
  final ValueChanged<String> onHomeFilterChanged;
  final ValueChanged<FeedSortMode> onHomeSortChanged;
  final ValueChanged<bool> onHomeFollowingChanged;
  final ValueChanged<bool> onReelsFilterChanged;

  static const labels = FeedTabLayout.labels;

  List<PopupMenuEntry<String>> _itemsForTab(int index) {
    if (FeedTabLayout.isReels(index)) {
      return reelsSourceFilterMenuItems(
        followingOnly: reelsFollowingOnly,
      );
    }
    return homeFeedFilterMenuItems(
      followingOnly: homeFollowingOnly,
      currentType: homeFeedType,
      currentSort: homeSortMode,
    );
  }

  void _onFilterSelected(int index, String value) {
    AppHaptics.selection();
    if (FeedTabLayout.isReels(index)) {
      onReelsFilterChanged(value == 'following');
      return;
    }
    if (value == 'source:following') {
      onHomeFollowingChanged(true);
      return;
    }
    if (value == 'source:recommended') {
      onHomeFollowingChanged(false);
      return;
    }
    if (value.startsWith('sort:')) {
      final sort = FeedSortMode.fromString(value.substring(5));
      if (sort != null) onHomeSortChanged(sort);
      return;
    }
    onHomeFilterChanged(value);
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
