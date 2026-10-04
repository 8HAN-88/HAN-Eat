import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/miniapps/data/miniapp_models.dart';
import 'package:han_eat/features/miniapps/data/miniapps_service.dart';
import 'package:han_eat/models/post.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/services/feed_service.dart';
import 'package:han_eat/utils/post_display_title.dart';
import 'package:han_eat/utils/shared_post_media.dart';

PostModel _parse(Map<String, dynamic> json) => PostModel.fromJson({
      'status': 'published',
      'created_at': '2026-01-01T00:00:00.000Z',
      'user_id': 1.0,
      'likes_count': 0,
      'comments_count': 0,
      'reposts_count': 0,
      'views_count': 0,
      'is_liked': false,
      ...json,
    });

void main() {
  test('text post shows caption and stays text', () {
    final post = _parse({
      'id': 1.0,
      'type': 'text',
      'title': 'Привет',
      'description': 'Первый пост',
    });
    expect(post.id, 1);
    expect(SharedPostMedia.kind(post), SharedPostKind.text);
    expect(SharedPostMedia.caption(post), 'Привет');
    expect(displayTitleForPost(post), 'Привет');
    expect(resolveFeedCaptionText(
      title: post.title,
      description: post.description,
    ), 'Привет\nПервый пост');
  });

  test('photo post from media[] and photos[] maps shows images', () {
    final fromMedia = _parse({
      'id': 2.0,
      'type': 'photo',
      'body': <dynamic, dynamic>{
        'media': [
          <dynamic, dynamic>{
            'type': 'image',
            'url': '/uploads/a.jpg',
          },
          <dynamic, dynamic>{
            'type': 'photo',
            'src': '/uploads/b.jpg',
          },
        ],
      },
    });
    expect(SharedPostMedia.kind(fromMedia), SharedPostKind.photo);
    expect(SharedPostMedia.imageUrls(fromMedia), [
      '/uploads/a.jpg',
      '/uploads/b.jpg',
    ]);

    final fromPhotos = _parse({
      'id': 3.0,
      'type': 'photo',
      'body': <dynamic, dynamic>{
        'photos': [
          '/uploads/c.jpg',
          <dynamic, dynamic>{'url': '/uploads/d.jpg'},
        ],
      },
    });
    expect(SharedPostMedia.firstImageUrl(fromPhotos), '/uploads/c.jpg');
    expect(SharedPostMedia.imageUrls(fromPhotos), [
      '/uploads/c.jpg',
      '/uploads/d.jpg',
    ]);
  });

  test('poll post parses web nums and loose option maps', () {
    final post = _parse({
      'id': 4.0,
      'type': 'poll',
      'title': 'Что выбрать',
      'body': <dynamic, dynamic>{
        'poll': <dynamic, dynamic>{
          'question': 'Обед?',
          'voted_option_index': 1.0,
          'is_closed': false,
          'options': [
            <dynamic, dynamic>{
              'text': 'Суп',
              'votes': 3.0,
              'percentage': 50.0,
              'index': 0.0,
            },
            <dynamic, dynamic>{
              'text': 'Салат',
              'votes': '3',
              'percentage': 50.0,
              'index': 1.0,
            },
          ],
        },
      },
    });
    final poll = post.poll;
    expect(poll, isNotNull);
    expect(poll!.question, 'Обед?');
    expect(poll.hasVoted, isTrue);
    expect(poll.votedOptionIndex, 1);
    expect(poll.options.map((e) => e.text), ['Суп', 'Салат']);
    expect(poll.options.map((e) => e.votes), [3, 3]);
  });

  test('link post keeps preview fields from loose meta', () {
    final post = _parse({
      'id': 5.0,
      'type': 'link',
      'body': <dynamic, dynamic>{
        'link_url': 'https://haneat.app',
        'link_preview': 'HanWe',
        'link_meta': <dynamic, dynamic>{
          'title': 'HanWe',
          'description': 'Мессенджер',
          'image': '/uploads/og.jpg',
          'domain': 'haneat.app',
        },
      },
    });
    expect(post.linkUrl, 'https://haneat.app');
    expect(post.linkTitle, 'HanWe');
    expect(post.linkDescription, 'Мессенджер');
    expect(post.linkImage, '/uploads/og.jpg');
    expect(post.linkDomain, 'haneat.app');
  });

  test('reel post still resolves playback and poster', () {
    final post = _parse({
      'id': 6.0,
      'type': 'reel',
      'body': <dynamic, dynamic>{
        'video_thumbnail': '/uploads/t.jpg',
        'media': [
          <dynamic, dynamic>{
            'type': 'reel',
            'url': 'https://cdn/original.mp4',
            'mp4_480p_url': 'https://cdn/480.mp4',
          },
        ],
      },
    });
    expect(SharedPostMedia.kind(post), SharedPostKind.video);
    expect(post.videoUrl, 'https://cdn/480.mp4');
    expect(SharedPostMedia.posterUrl(post), '/uploads/t.jpg');
  });

  test('channel post keeps author and channel from loose maps', () {
    final post = _parse({
      'id': 7.0,
      'type': 'photo',
      'channel_id': 21.0,
      'title': 'Новость',
      'author': <dynamic, dynamic>{'id': 9.0, 'name': 'Редактор'},
      'channel': <dynamic, dynamic>{
        'id': 21.0,
        'name': 'HAN',
        'slug': 'han',
      },
      'body': <dynamic, dynamic>{
        'photos': ['/uploads/ch.jpg'],
      },
    });
    expect(post.channelId, 21);
    expect(post.author?.name, 'Редактор');
    expect(post.channel?.name, 'HAN');
    expect(SharedPostMedia.firstImageUrl(post), '/uploads/ch.jpg');
  });

  test('feed response keeps every publishable kind from loose maps', () {
    final feed = FeedResponse.fromJson({
      'has_more': false,
      'items': [
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 1.0,
          'type': 'text',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 1,
          'title': 'Текст',
        },
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 2.0,
          'type': 'photo',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 1,
          'body': {
            'photos': ['/uploads/a.jpg'],
          },
        },
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 3.0,
          'type': 'poll',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 1,
          'body': {
            'poll': {
              'question': '?',
              'options': [
                {'text': 'Да', 'votes': 1.0, 'index': 0.0},
              ],
            },
          },
        },
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 4.0,
          'type': 'link',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 1,
          'body': {'link_url': 'https://haneat.app'},
        },
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 5.0,
          'type': 'reel',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 1,
          'body': {
            'media': [
              {'type': 'reel', 'url': 'https://cdn/v.mp4'},
            ],
          },
        },
      ],
    });
    expect(feed.items.map((e) => e.type), [
      'text',
      'photo',
      'poll',
      'link',
      'reel',
    ]);
    expect(feed.items[1].poll, isNull);
    expect(feed.items[2].poll?.question, '?');
    expect(SharedPostMedia.firstImageUrl(feed.items[1]), '/uploads/a.jpg');
    expect(feed.items[3].linkUrl, 'https://haneat.app');
    expect(feed.items[4].videoUrl, 'https://cdn/v.mp4');
  });

  test('mini-app catalog keeps loose maps and skips empty urls', () {
    final apps = MiniAppsService.parseItemList({
      'items': [
        <dynamic, dynamic>{
          'id': 8.0,
          'bot_id': 3.0,
          'bot_username': 'shopbot',
          'bot_name': 'Shop',
          'name': 'Магазин',
          'short_name': 'shop',
          'url': 'https://shop.example/app',
          'icon_url': '/uploads/icon.png',
          'category': 'shopping',
          'is_official': true,
          'moderation_status': 'approved',
        },
        <dynamic, dynamic>{
          'id': 9.0,
          'bot_id': 4.0,
          'name': 'Пустой',
          'short_name': 'empty',
          'url': '',
        },
        'bad',
      ],
    });
    expect(apps, hasLength(1));
    expect(apps.single.id, 8);
    expect(apps.single.botId, 3);
    expect(apps.single.name, 'Магазин');
    expect(apps.single.categoryLabel, 'Покупки');
    expect(apps.single.isApproved, isTrue);
    expect(apps.single.url, 'https://shop.example/app');
  });

  test('mini-app launch context accepts web nums and loose init data', () {
    final launch = MiniAppLaunchContext.fromJson({
      'miniapp_id': 8.0,
      'url': 'https://shop.example/app',
      'init_data': 'user=%7B%7D',
      'init_data_unsafe': <dynamic, dynamic>{
        'user': <dynamic, dynamic>{'id': 11.0, 'name': 'Анна'},
      },
    });
    expect(launch.miniappId, 8);
    expect(launch.url, 'https://shop.example/app');
    expect(launch.initDataUnsafe['user'], isA<Map>());
  });

  test('legacy recipe body still yields a showable title and image', () {
    expect(
      resolvePostDisplayTitle(
        title: 'recipe',
        body: <dynamic, dynamic>{
          'recipe': <dynamic, dynamic>{'title': 'Борщ', 'image': '/uploads/b.jpg'},
        },
      ),
      'Борщ',
    );
    expect(
      extractLegacyBodyImageUrl(<dynamic, dynamic>{
        'recipe': <dynamic, dynamic>{'source_image': '/uploads/b.jpg'},
      }),
      '/uploads/b.jpg',
    );
  });
}
