import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/models/video_quality_preference.dart';

void main() {
  test('videoUrl uses auto fast start (480p without HLS)', () {
    final post = PostModel(
      id: 1,
      type: 'reel',
      status: 'published',
      createdAt: DateTime(2024),
      userId: 1,
      likesCount: 0,
      commentsCount: 0,
      repostsCount: 0,
      viewsCount: 0,
      isLiked: false,
      body: {
        'media': [
          {
            'type': 'video',
            'url': 'https://api.haneat.app/uploads/original.mp4',
            'mp4_720p_url': 'https://api.haneat.app/uploads/original_720p.mp4',
            'mp4_480p_url': 'https://api.haneat.app/uploads/original_480p.mp4',
          },
        ],
      },
    );

    expect(
      post.videoUrl,
      'https://api.haneat.app/uploads/original_480p.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.hd720),
      'https://api.haneat.app/uploads/original_720p.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.max),
      'https://api.haneat.app/uploads/original_720p.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.hd1080),
      'https://api.haneat.app/uploads/original_720p.mp4',
    );
  });

  test('commentsCount uses preview when API count is stale', () {
    final post = PostModel.fromJson({
      'id': 7,
      'type': 'reel',
      'status': 'published',
      'created_at': '2026-01-01T00:00:00.000Z',
      'user_id': 1,
      'likes_count': 0,
      'comments_count': 0,
      'reposts_count': 0,
      'views_count': 0,
      'is_liked': false,
      'preview_comments': [
        {
          'id': 1,
          'user_id': 1,
          'author_name': 'HAN',
          'text': '.',
        },
      ],
    });
    expect(post.commentsCount, 1);
  });

  test('commentsCount reads numeric string', () {
    final post = PostModel.fromJson({
      'id': 8,
      'type': 'reel',
      'status': 'published',
      'created_at': '2026-01-01T00:00:00.000Z',
      'user_id': 1,
      'likes_count': '2',
      'comments_count': '3',
      'reposts_count': 1.0,
      'views_count': 0,
      'is_liked': false,
    });
    expect(post.likesCount, 2);
    expect(post.commentsCount, 3);
    expect(post.repostsCount, 1);
  });
}
