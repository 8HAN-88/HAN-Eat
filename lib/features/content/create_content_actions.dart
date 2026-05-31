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

/// Выбор: обычный пост или рилс.
Future<void> showCreateContentSheet(BuildContext context, {WidgetRef? ref}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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

  if (!context.mounted || choice == null) return;
  if (choice == 'post') {
    await context.push(CreatePostRoute.path);
  }
}
