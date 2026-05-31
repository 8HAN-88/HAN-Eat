import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';

/// Меню создания контента внутри канала (пост, рецепт, рилс).
void showChannelCreateContentSheet(
  BuildContext context, {
  required int channelId,
  String? channelName,
}) {
  showModalBottomSheet<void>(
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
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push(
                ChannelDetailRoute.createPost(
                  channelId,
                  channelName: channelName,
                  type: 'reel',
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Создать рецепт'),
            subtitle: const Text('Публичный в Menu или приватный в канале'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              if (channelName != null && channelName.trim().isNotEmpty) {
                context.push(
                  ChannelDetailRoute.createRecipe(channelId, channelName),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Пост с фото'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push(
                ChannelDetailRoute.createPost(
                  channelId,
                  channelName: channelName,
                  type: 'photo',
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Текстовый пост'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push(
                ChannelDetailRoute.createPost(
                  channelId,
                  channelName: channelName,
                  type: 'text',
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
