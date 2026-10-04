import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/ads/ads_order.dart';
import 'package:han_eat/services/ads_service.dart';
import 'package:han_eat/services/feed_service.dart';
import 'package:han_eat/services/server_config.dart';

void main() {
  test('created campaign parses web nums and loose creative maps', () {
    final campaign = AdCampaign.fromJson({
      'id': 7.0,
      'advertiser_id': '3',
      'name': 'Лето',
      'status': 'draft',
      'is_live': false,
      'surfaces': ['feed', 'reels'],
      'destination_type': 'url',
      'destination_url': 'https://haneat.app',
      'destination_channel_id': 21.0,
      'destination_post_id': '15',
      'daily_cap': 100.0,
      'creative': <dynamic, dynamic>{
        'id': 11.0,
        'title': 'Заголовок',
        'body': 'Текст',
        'cta_label': 'Открыть',
        'image_url': '/uploads/ad.jpg',
        'advertiser_name': 'HanWe',
      },
      'ready_to_submit': true,
    });
    expect(campaign.id, 7);
    expect(campaign.advertiserId, 3);
    expect(campaign.destinationChannelId, 21);
    expect(campaign.destinationPostId, 15);
    expect(campaign.dailyCap, 100);
    expect(campaign.canSubmit, isTrue);
    expect(campaign.creative.id, 11);
    expect(campaign.creative.title, 'Заголовок');
    expect(campaign.creative.imageUrl, '/uploads/ad.jpg');
    expect(
      ServerConfig.resolveMediaUrl(campaign.creative.imageUrl!),
      contains('ad.jpg'),
    );
  });

  test('advertiser cabinet list keeps loose campaign maps', () {
    final campaigns = AdsService.parseCampaignList({
      'campaigns': [
        <dynamic, dynamic>{
          'id': 8.0,
          'advertiser_id': 1.0,
          'name': 'Оффер',
          'status': 'approved',
          'is_live': true,
          'surfaces': ['feed'],
          'creative': <dynamic, dynamic>{'title': 'Кофе'},
        },
        <dynamic, dynamic>{'id': 0, 'name': 'пустая'},
        'bad',
      ],
    });
    expect(campaigns, hasLength(1));
    expect(campaigns.single.id, 8);
    expect(campaigns.single.isLive, isTrue);
    expect(campaigns.single.creative.title, 'Кофе');
    expect(campaigns.single.statusLabel, 'В эфире');
  });

  test('feed ad shows from flat inventory and nested campaign payload', () {
    final flat = AdsService.parseFeedAd({
      'kind': 'ad',
      'campaign_id': '77',
      'title': 'Оффер',
      'body': 'Скидка',
      'cta_label': 'Открыть',
      'image_url': '/uploads/ad.jpg',
      'advertiser_name': 'Cafe',
      'destination_type': 'url',
      'destination_url': 'cafe.example',
      'surface': 'feed',
    });
    expect(flat, isNotNull);
    expect(flat!.campaignId, 77);
    expect(flat.title, 'Оффер');
    expect(flat.imageUrl, '/uploads/ad.jpg');
    expect(flat.asCampaign.creative.title, 'Оффер');
    expect(
      ServerConfig.resolveMediaUrl(flat.imageUrl!),
      contains('ad.jpg'),
    );

    final nested = AdsService.parseFeedAd({
      'kind': 'ad',
      'campaign_id': 9.0,
      'campaign': <dynamic, dynamic>{
        'id': 9.0,
        'destination_type': 'channel',
        'destination_channel_id': 21.0,
        'creative': <dynamic, dynamic>{
          'id': 4.0,
          'title': 'Канал',
          'body': 'Подпишись',
          'cta_label': 'Открыть',
          'image_url': '/uploads/ch.jpg',
          'advertiser_name': 'HAN',
        },
      },
    });
    expect(nested, isNotNull);
    expect(nested!.campaignId, 9);
    expect(nested.title, 'Канал');
    expect(nested.destinationType, 'channel');
    expect(nested.destinationChannelId, 21);
    expect(nested.ctaLabel, 'Открыть');
  });

  test('published feed mixes posts and an ad card slot', () {
    final feed = FeedResponse.fromJson({
      'has_more': false,
      'items': [
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 1.0,
          'type': 'text',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 2,
          'title': 'Пост',
        },
        <dynamic, dynamic>{
          'kind': 'ad',
          'campaign_id': 77.0,
          'title': 'Оффер',
          'cta_label': 'Открыть',
          'image_url': '/uploads/ad.jpg',
          'destination_type': 'url',
          'destination_url': 'https://haneat.app',
        },
        <dynamic, dynamic>{
          'kind': 'post',
          'id': 2.0,
          'type': 'photo',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 2,
        },
      ],
    });
    expect(feed.items.map((e) => e.id), [1, 2]);
    expect(feed.ads.single.item.campaignId, 77);
    expect(feed.ads.single.insertBeforePostIndex, 1);
    final rows = mergeFeedRows(posts: feed.items, ads: feed.ads);
    expect(rows.map((e) => e.isAd).toList(), [false, true, false]);
    expect(rows[1].ad?.title, 'Оффер');
    expect(rows[1].ad?.imageUrl, '/uploads/ad.jpg');
  });

  test('ad order is ready to publish with url, channel or post dest', () {
    expect(
      validateAdOrder(
        surfaces: {'feed'},
        title: 'Кофе',
        body: 'С собой',
        imageUrl: '/uploads/ad.jpg',
        destinationType: 'url',
        destinationUrl: 'cafe.example',
        channelId: null,
        postIdRaw: '',
      ),
      isEmpty,
    );
    expect(
      validateAdOrder(
        surfaces: {'feed', 'reels'},
        title: 'Канал',
        body: '',
        imageUrl: '/uploads/ad.jpg',
        destinationType: 'channel',
        destinationUrl: '',
        channelId: 21,
        postIdRaw: '',
      ),
      isEmpty,
    );
    expect(
      validateAdOrder(
        surfaces: {'feed'},
        title: 'Пост',
        body: 'Читать',
        imageUrl: null,
        destinationType: 'post',
        destinationUrl: '',
        channelId: null,
        postIdRaw: 'https://haneat.app/post/88',
      ),
      isEmpty,
    );
  });
}
