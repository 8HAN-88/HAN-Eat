import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/utils/shared_post_media.dart';

PostModel _post({
  required String type,
  Map<String, dynamic>? body,
  String? title,
  String? description,
}) {
  return PostModel(
    id: 1,
    type: type,
    title: title,
    description: description,
    status: 'published',
    createdAt: DateTime(2026),
    userId: 1,
    likesCount: 0,
    commentsCount: 0,
    repostsCount: 0,
    viewsCount: 0,
    isLiked: false,
    body: body,
  );
}

void main() {
  group('SharedPostMedia', () {
    test('treats reels and video media as video', () {
      expect(SharedPostMedia.isVideo(_post(type: 'reel')), isTrue);
      expect(
        SharedPostMedia.isVideo(
          _post(
            type: 'photo',
            body: {
              'media': [
                {
                  'type': 'video',
                  'url': 'https://cdn/v.mp4',
                  'thumbnail_url': 'https://cdn/t.jpg',
                },
              ],
            },
          ),
        ),
        isTrue,
      );
      expect(
        SharedPostMedia.isVideo(
          _post(
            type: 'photo',
            body: {
              'media': [
                {'type': 'image', 'url': 'https://cdn/a.jpg'},
              ],
            },
          ),
        ),
        isFalse,
      );
    });

    test('reads first image and video poster', () {
      final photo = _post(
        type: 'photo',
        body: {
          'media': [
            {'type': 'image', 'url': 'https://cdn/a.jpg'},
          ],
        },
      );
      expect(SharedPostMedia.firstImageUrl(photo), 'https://cdn/a.jpg');
      expect(SharedPostMedia.posterUrl(photo), 'https://cdn/a.jpg');

      final reel = _post(
        type: 'reel',
        body: {
          'video_thumbnail': 'https://cdn/thumb.jpg',
          'media': [
            {'type': 'video', 'url': 'https://cdn/v.mp4'},
          ],
        },
      );
      expect(SharedPostMedia.posterUrl(reel), 'https://cdn/thumb.jpg');
    });

    test('prefers meaningful title over description', () {
      final post = _post(
        type: 'photo',
        title: 'Команды',
        description: 'длинный текст',
      );
      expect(SharedPostMedia.caption(post), 'Команды');
    });
  });
}
