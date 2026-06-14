import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/services/feed_api_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedApiCache', () {
    test('save and load round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final posts = [
        PostModel(
          id: 1,
          type: 'text',
          status: 'published',
          createdAt: DateTime(2026, 1, 1),
          userId: 42,
          likesCount: 0,
          commentsCount: 0,
          repostsCount: 0,
          viewsCount: 0,
          isLiked: false,
          title: 'Test post',
        ),
      ];

      await FeedApiCache.save('rec_all', posts);
      final loaded = await FeedApiCache.load('rec_all');

      expect(loaded.length, 1);
      expect(loaded.first.id, 1);
      expect(loaded.first.title, 'Test post');
    });

    test('load returns empty for unknown variant', () async {
      SharedPreferences.setMockInitialValues({});
      final loaded = await FeedApiCache.load('missing');
      expect(loaded, isEmpty);
    });
  });
}
