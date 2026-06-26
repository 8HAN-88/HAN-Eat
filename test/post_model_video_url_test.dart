import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/models/video_quality_preference.dart';

void main() {
  test('videoUrl uses auto fast start (720p without HLS)', () {
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
      'https://api.haneat.app/uploads/original_720p.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.hd720),
      'https://api.haneat.app/uploads/original_720p.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.max),
      'https://api.haneat.app/uploads/original.mp4',
    );
    expect(
      post.videoUrlFor(VideoQualityPreference.hd1080),
      'https://api.haneat.app/uploads/original.mp4',
    );
  });
}
