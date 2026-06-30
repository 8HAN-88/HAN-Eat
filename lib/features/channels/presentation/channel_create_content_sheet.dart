import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/app/app_variant.dart';
import '../../../widgets/telegram_ui.dart';
import '../../content/create_content_actions.dart';

/// Меню создания контента внутри канала (пост, рецепт, рилс).
///
/// Возвращает `true`, если рилс был создан.
Future<bool> showChannelCreateContentSheet(
  BuildContext context, {
  required int channelId,
  String? channelName,
}) async {
  String? choice;
  await showTelegramActionSheet<void>(
    context: context,
    title: 'Создать',
    actions: [
      TelegramActionSheetAction(
        icon: Icons.videocam_outlined,
        title: 'Создать рилс',
        subtitle: 'Короткое видео в ленту рилсов',
        onTap: () => choice = 'reel',
      ),
      if (AppVariant.current.isKitchen)
        TelegramActionSheetAction(
          icon: Icons.restaurant_menu,
          title: 'Создать рецепт',
          subtitle: 'Публичный в Menu или приватный в канале',
          onTap: () => choice = 'recipe',
        ),
      TelegramActionSheetAction(
        icon: Icons.photo_library_outlined,
        title: 'Пост с фото',
        onTap: () => choice = 'photo',
      ),
      TelegramActionSheetAction(
        icon: Icons.text_fields,
        title: 'Текстовый пост',
        onTap: () => choice = 'text',
      ),
    ],
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
      type: choice!,
    ),
  );
  return false;
}
