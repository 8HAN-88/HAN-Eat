import 'package:flutter/material.dart';

import '../../../models/post_types.dart';

/// Пункты фильтра контента ленты (подписки / рекомендации).
List<PopupMenuEntry<String>> feedContentFilterMenuItems(String current) {
  final options = <String, String>{
    'all': 'Все',
    'photos': 'Фото',
    'reels': 'Рилсы',
  };
  return options.entries
      .map(
        (e) => PopupMenuItem<String>(
          value: e.key,
          child: Text(
            e.value,
            style: TextStyle(
              fontWeight: current == e.key ? FontWeight.bold : null,
            ),
          ),
        ),
      )
      .toList();
}

/// Фильтр контента + сортировка (подписки / рекомендации).
List<PopupMenuEntry<String>> feedTabFilterMenuItems({
  required String currentType,
  required FeedSortMode currentSort,
}) {
  return [
    ...feedContentFilterMenuItems(currentType),
    const PopupMenuDivider(),
    const PopupMenuItem<String>(
      enabled: false,
      child: Text(
        'Сортировка',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    for (final mode in FeedSortMode.values)
      PopupMenuItem<String>(
        value: 'sort:${mode.value}',
        child: Text(
          mode.label,
          style: TextStyle(
            fontWeight: currentSort == mode ? FontWeight.bold : null,
          ),
        ),
      ),
  ];
}

/// Источник одной домашней ленты: подписки или рекомендации.
List<PopupMenuEntry<String>> homeFeedFilterMenuItems({
  required bool followingOnly,
  required String currentType,
  required FeedSortMode currentSort,
}) {
  return [
    const PopupMenuItem<String>(
      enabled: false,
      child: Text(
        'Лента',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    PopupMenuItem<String>(
      value: 'source:following',
      child: Text(
        'Подписки',
        style: TextStyle(
          fontWeight: followingOnly ? FontWeight.bold : null,
        ),
      ),
    ),
    PopupMenuItem<String>(
      value: 'source:recommended',
      child: Text(
        'Рекомендации',
        style: TextStyle(
          fontWeight: !followingOnly ? FontWeight.bold : null,
        ),
      ),
    ),
    const PopupMenuDivider(),
    ...feedTabFilterMenuItems(
      currentType: currentType,
      currentSort: currentSort,
    ),
  ];
}

/// Пункты фильтра вкладки «Рилсы».
List<PopupMenuEntry<String>> reelsSourceFilterMenuItems({
  required bool followingOnly,
}) {
  return [
    PopupMenuItem<String>(
      value: 'all',
      child: Text(
        'Все',
        style: TextStyle(
          fontWeight: !followingOnly ? FontWeight.bold : null,
        ),
      ),
    ),
    PopupMenuItem<String>(
      value: 'following',
      child: Text(
        'Подписки',
        style: TextStyle(
          fontWeight: followingOnly ? FontWeight.bold : null,
        ),
      ),
    ),
  ];
}
