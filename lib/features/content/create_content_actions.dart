import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../services/feed_api_cache.dart';
import '../community/presentation/community_upload_screen.dart';
import '../reels/application/reels_feed_refresh_provider.dart';

/// Открыть экран загрузки рилса (community video API).
Future<bool?> openCreateReel(BuildContext context, {WidgetRef? ref}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => const CommunityUploadScreen(),
    ),
  );
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
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeReel)
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Рилс'),
              subtitle: const Text('Короткое видео в ленту рилсов'),
              onTap: () => Navigator.pop(ctx, 'reel'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Пост'),
            subtitle: const Text('Текст, фото, рецепт, опрос'),
            onTap: () => Navigator.pop(ctx, 'post'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (!context.mounted || choice == null) return false;

  if (choice == 'reel') {
    final created = await openCreateReel(context, ref: ref);
    return created == true;
  }

  final postResult = await context.push<bool?>(CreatePostRoute.path);
  return postResult == true;
}
