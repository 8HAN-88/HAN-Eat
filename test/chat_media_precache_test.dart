import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_media_precache.dart';
import 'package:han_eat/models/chat_models.dart';
import 'package:han_eat/models/post_model.dart';

void main() {
  test('chatMessageMediaUrls prefers the latest photos', () {
    ChatMessage msg(int id, String type, String url) => ChatMessage(
          id: id,
          conversationId: 1,
          senderId: 1,
          type: type,
          content: '',
          mediaUrl: url,
          createdAt: DateTime.utc(2026, 1, id),
        );

    final urls = chatMessageMediaUrls([
      msg(1, 'image', 'https://cdn/old.jpg'),
      msg(2, 'text', ''),
      msg(3, 'image', 'https://cdn/new.jpg'),
    ], limit: 1);

    expect(urls, ['https://cdn/new.jpg']);
  });

  test('channelPostMediaUrls keeps thumbs and photos', () {
    final post = PostModel.fromJson({
      'id': 7,
      'type': 'photo',
      'status': 'published',
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': 1,
      'likes_count': 0,
      'comments_count': 0,
      'reposts_count': 0,
      'views_count': 0,
      'body': {
        'video_thumbnail': 'https://cdn/thumb.jpg',
        'media': [
          {'type': 'image', 'url': 'https://cdn/a.jpg'},
          {'type': 'video', 'url': 'https://cdn/v.mp4', 'thumbnail': 'https://cdn/v.jpg'},
        ],
      },
    });

    final urls = channelPostMediaUrls([post], limit: 8);
    expect(urls, contains('https://cdn/thumb.jpg'));
    expect(urls, contains('https://cdn/a.jpg'));
    expect(urls, contains('https://cdn/v.jpg'));
  });
}
