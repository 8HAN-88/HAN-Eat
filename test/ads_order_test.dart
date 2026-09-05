import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/ads/ads_order.dart';
import 'package:han_eat/services/ads_service.dart';
import 'package:han_eat/services/feed_service.dart';

void main() {
  test('parseAdPostId accepts number and url', () {
    expect(parseAdPostId('42'), 42);
    expect(parseAdPostId('https://haneat.app/post/88'), 88);
    expect(parseAdPostId('https://haneat.app/channel/1/post/15'), 15);
    expect(parseAdPostId('нет'), isNull);
  });

  test('validateAdOrder asks for the missing client fields', () {
    final issues = validateAdOrder(
      surfaces: {},
      title: '',
      body: '',
      imageUrl: null,
      destinationType: 'url',
      destinationUrl: 'нет ссылки',
      channelId: null,
      postIdRaw: '',
    );
    expect(issues.map((e) => e.field), containsAll(['surfaces', 'title', 'creative', 'destination']));
    expect(
      validateAdOrder(
        surfaces: {'feed'},
        title: 'Кофе',
        body: 'С собой',
        imageUrl: null,
        destinationType: 'url',
        destinationUrl: 'cafe.example',
        channelId: null,
        postIdRaw: '',
      ),
      isEmpty,
    );
    expect(normalizeAdDestinationUrl('site.ru'), 'https://site.ru');
    expect(isAdDestinationUrl('site.ru'), isTrue);
    expect(isAdDestinationUrl('нет'), isFalse);
  });

  test('mergeFeedRows inserts an ad before the given post index', () {
    final rows = mergeFeedRows(
      posts: ['a', 'b', 'c'],
      ads: [
        FeedAdPlacement(
          insertBeforePostIndex: 2,
          item: FeedAdItem(
            campaignId: 9,
            title: 'Реклама',
            body: '',
            ctaLabel: 'Открыть',
            destinationType: 'url',
            destinationUrl: 'https://haneat.app',
          ),
        ),
      ],
    );
    expect(rows.map((e) => e.isAd).toList(), [false, false, true, false]);
    expect(rows[2].ad?.campaignId, 9);
  });

  test('FeedResponse keeps posts and records ad slots', () {
    final response = FeedResponse.fromJson({
      'items': [
        {
          'id': 1,
          'kind': 'post',
          'type': 'text',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 2,
        },
        {
          'kind': 'ad',
          'campaign_id': 77,
          'title': 'Оффер',
          'cta_label': 'Открыть',
          'destination_type': 'url',
          'destination_url': 'https://haneat.app',
        },
        {
          'id': 2,
          'kind': 'post',
          'type': 'text',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 2,
        },
      ],
      'has_more': false,
    });
    expect(response.items.map((e) => e.id), [1, 2]);
    expect(response.ads, hasLength(1));
    expect(response.ads.single.insertBeforePostIndex, 1);
    expect(response.ads.single.item.title, 'Оффер');
  });
}
