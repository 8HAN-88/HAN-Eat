import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/services/channel_cache_service.dart';
import 'package:han_eat/services/channel_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ChannelCacheService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('loadCachedPosts returns posts older than 5 minutes', () async {
    final posts = [
      PostModel(
        id: 9,
        type: 'text',
        status: 'published',
        createdAt: DateTime(2026, 8, 1),
        userId: 1,
        likesCount: 0,
        commentsCount: 0,
        repostsCount: 0,
        viewsCount: 0,
        isLiked: false,
        title: 'Stale',
        description: 'Что то Voy',
      ),
    ];
    await ChannelCacheService.saveCachedPosts(
      channelId: 7,
      posts: posts,
    );
    ChannelCacheService.resetForTest();

    final prefs = await SharedPreferences.getInstance();
    final key = ChannelCacheService.postsCacheKey(channelId: 7);
    await prefs.setString(
      'channel_cache_timestamp_$key',
      DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
    );

    final loaded = await ChannelCacheService.loadCachedPosts(
      channelId: 7,
      allowStale: true,
    );
    expect(loaded, isNotNull);
    expect(loaded!.single.id, 9);
    expect(loaded.single.description, 'Что то Voy');
  });

  test('loadCachedChannel returns expired header', () async {
    final channel = ChannelDetail(
      id: 3,
      name: 'HAN',
      slug: 'han',
      adminUserId: 1,
      isPublic: true,
      membersCount: 1,
      postsCount: 4,
      createdAt: DateTime(2026, 1, 1),
      autoPublishReels: true,
      isMember: true,
      isAdmin: true,
      isOwner: true,
      isModerator: false,
    );
    SharedPreferences.setMockInitialValues({
      'channel_cache_3': jsonEncode(channel.toJson()),
      'channel_cache_timestamp_3':
          DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    });

    final loaded = await ChannelCacheService.loadCachedChannel(3);
    expect(loaded, isNotNull);
    expect(loaded!.name, 'HAN');
    expect(loaded.canViewPosts, isTrue);
  });
}
