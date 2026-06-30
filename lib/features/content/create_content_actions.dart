import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../core/app/app_variant.dart';
import '../../services/feed_api_cache.dart';
import '../../widgets/telegram_ui.dart';
import '../reels/application/reels_feed_refresh_provider.dart';

/// Открыть экран загрузки рилса (community video API).
///
/// [channelId] — рилс публикуется в канал (как пост канала + опционально в Reels).
Future<bool?> openCreateReel(
  BuildContext context, {
  WidgetRef? ref,
  int? channelId,
  String? channelName,
}) async {
  final route = channelId != null
      ? CreateReelRoute.uri(channelId: channelId, channelName: channelName)
      : CreateReelRoute.path;
  final created = await context.push<bool?>(route);
  if (created == true) {
    await FeedApiCache.clear('rec_reels');
    if (ref != null) {
      notifyReelsFeedRefresh(ref);
    } else {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        container.read(reelsFeedRefreshProvider.notifier).state++;
      } catch (_) {}
    }
  }
  return created;
}

/// Выбор: обычный пост и (опционально) рилс в ленту.
///
/// [includeReel] — для профиля; на главной не используется.
Future<bool> showCreateContentSheet(
  BuildContext context, {
  WidgetRef? ref,
  bool includeReel = false,
}) async {
  // В kitchen показываем только создание рецепта
  if (AppVariant.current.isKitchen) {
    final created = await context.push<bool?>(CreateRecipeRoute.path);
    return created == true;
  }

  String? choice;
  await showTelegramActionSheet<void>(
    context: context,
    title: 'Создать',
    actions: [
      if (includeReel)
        TelegramActionSheetAction(
          icon: Icons.videocam_outlined,
          title: 'Рилс',
          subtitle: 'Короткое видео в ленту рилсов',
          onTap: () => choice = 'reel',
        ),
      TelegramActionSheetAction(
        icon: Icons.edit_outlined,
        title: 'Пост',
        subtitle: 'Текст, фото, ссылка или опрос',
        onTap: () => choice = 'post',
      ),
    ],
  );

  if (!context.mounted || choice == null) return false;

  if (choice == 'reel') {
    final created = await openCreateReel(context, ref: ref);
    return created == true;
  }

  final postResult = await context.push<bool?>(CreatePostRoute.path);
  return postResult == true;
}
