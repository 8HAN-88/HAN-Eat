import 'package:flutter/material.dart';

/// Пункты фильтра контента ленты (подписки / рекомендации).
List<PopupMenuEntry<String>> feedContentFilterMenuItems(String current) {
  const options = <String, String>{
    'all': 'Все',
    'photos': 'Фото',
    'recipes': 'Рецепты',
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
