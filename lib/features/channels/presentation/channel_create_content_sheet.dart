import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../widgets/telegram_ui.dart';
import '../../content/create_content_actions.dart';

/// Меню создания контента внутри канала (пост, рилс).
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

  final result = await context.push(
    ChannelDetailRoute.createPost(
      channelId,
      channelName: channelName,
      type: choice!,
    ),
  );
  return result == true || result != null;
}
