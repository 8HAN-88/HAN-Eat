import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../content/create_content_actions.dart';

/// Меню создания контента внутри канала (пост, рецепт, рилс).
///
/// Возвращает `true`, если рилс был создан.
Future<bool> showChannelCreateContentSheet(
  BuildContext context, {
  required int channelId,
  String? channelName,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Создать рилс'),
            subtitle: const Text('Короткое видео в ленту рилсов'),
            onTap: () => Navigator.of(sheetContext).pop('reel'),
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Создать рецепт'),
            subtitle: const Text('Публичный в Menu или приватный в канале'),
            onTap: () => Navigator.of(sheetContext).pop('recipe'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Пост с фото'),
            onTap: () => Navigator.of(sheetContext).pop('photo'),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Текстовый пост'),
            onTap: () => Navigator.of(sheetContext).pop('text'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted || choice == null) return false;

  if (choice == 'reel') {
    final created = await openCreateReel(
      context,
      channelId: channelId,
      channelName: channelName,
    );
    return created == true;
  }

  if (choice == 'recipe') {
    if (channelName != null && channelName.trim().isNotEmpty) {
      await context.push(
        ChannelDetailRoute.createRecipe(channelId, channelName),
      );
    }
    return false;
  }

  await context.push(
    ChannelDetailRoute.createPost(
      channelId,
      channelName: channelName,
      type: choice,
    ),
  );
  return false;
}
