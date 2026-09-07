import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/stories/data/story_models.dart';
import 'package:han_eat/services/story_feed_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StoryFeedCache keeps live stories and drops expired', () async {
    SharedPreferences.setMockInitialValues({});
    final live = StoryDto(
      id: 1,
      userId: 9,
      mediaUrl: 'https://cdn.example/s.jpg',
      mediaType: 'image',
      visibility: 'public',
      viewsCount: 0,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      author: const StoryAuthor(id: 9, name: 'Анна'),
    );
    final expired = StoryDto(
      id: 2,
      userId: 8,
      mediaUrl: 'https://cdn.example/old.jpg',
      mediaType: 'image',
      visibility: 'public',
      viewsCount: 0,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      author: const StoryAuthor(id: 8, name: 'Старое'),
    );

    await StoryFeedCache.save([live, expired]);
    expect(StoryFeedCache.peek().map((e) => e.id), [1]);

    await StoryFeedCache.warmUp();
    expect(StoryFeedCache.peek().single.author.name, 'Анна');
  });
}
