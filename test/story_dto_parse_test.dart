import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/stories/data/story_models.dart';
import 'package:han_eat/features/stories/data/story_service.dart';

void main() {
  final now = DateTime.now().toUtc();
  final later = now.add(const Duration(hours: 8));

  test('StoryDto.fromJson accepts web-style nums and loose author maps', () {
    final story = StoryDto.fromJson({
      'id': 28.0,
      'user_id': 11.0,
      'media_url': '/uploads/stories/s.jpg',
      'thumbnail_url': '/uploads/stories/t.jpg',
      'media_type': 'image',
      'views_count': 3.0,
      'created_at': now.toIso8601String(),
      'expires_at': later.toIso8601String(),
      'author': <dynamic, dynamic>{
        'id': 11.0,
        'name': 'Анна',
        'username': 'anna',
      },
    });

    expect(story.id, 28);
    expect(story.userId, 11);
    expect(story.mediaUrl, '/uploads/stories/s.jpg');
    expect(story.viewsCount, 3);
    expect(story.author.id, 11);
    expect(story.author.name, 'Анна');
    expect(story.isPlayable, isTrue);
    expect(story.isExpired, isFalse);
  });

  test('parseStoryList skips broken items and keeps playable ones', () {
    final stories = StoryService.parseStoryList([
      {
        'id': 1.0,
        'user_id': 9.0,
        'media_url': 'https://cdn.haneat.com/uploads/ok.jpg',
        'media_type': 'image',
        'created_at': now.toIso8601String(),
        'expires_at': later.toIso8601String(),
        'author': {'id': 9.0, 'name': 'Ок'},
      },
      {
        'id': 2,
        'user_id': 8,
        'media_url': '',
        'created_at': now.toIso8601String(),
        'expires_at': later.toIso8601String(),
      },
      'bad',
      {
        'items': 'nope',
      },
    ]);

    expect(stories.map((e) => e.id), [1]);
    expect(stories.single.author.name, 'Ок');
  });

  test('parseStoryList reads wrapped items payload', () {
    final stories = StoryService.parseStoryList({
      'items': [
        {
          'id': '7',
          'user_id': '4',
          'media_url': 'https://cdn.example/s.jpg',
          'media_type': 'video',
          'created_at': now.toIso8601String(),
          'expires_at': later.toIso8601String(),
          'author': {'id': '4', 'name': 'Видео'},
        },
      ],
    });
    expect(stories.single.id, 7);
    expect(stories.single.isVideo, isTrue);
  });
}
