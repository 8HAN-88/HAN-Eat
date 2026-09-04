import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/ads_service.dart';
import 'package:han_eat/services/feed_service.dart';

void main() {
  test('AdCampaign.fromJson maps cabinet payload', () {
    final campaign = AdCampaign.fromJson({
      'id': 7,
      'advertiser_id': 3,
      'name': 'Лето',
      'status': 'pending_review',
      'is_live': false,
      'surfaces': ['feed', 'reels'],
      'destination_type': 'url',
      'destination_url': 'https://haneat.app',
      'creative': {
        'id': 11,
        'title': 'Заголовок',
        'body': 'Текст',
        'cta_label': 'Открыть',
        'image_url': 'https://cdn.example/ad.jpg',
        'advertiser_name': 'HanWe',
      },
    });

    expect(campaign.id, 7);
    expect(campaign.statusLabel, 'На модерации');
    expect(campaign.surfacesLabel, 'Лента · Рилсы');
    expect(campaign.canSubmit, isTrue);
    expect(campaign.creative.title, 'Заголовок');
    expect(campaign.creative.ctaLabel, 'Открыть');
  });

  test('FeedResponse skips unknown item kinds such as ads', () {
    final response = FeedResponse.fromJson({
      'items': [
        {
          'kind': 'ad',
          'campaign_id': 1,
          'title': 'Реклама',
        },
        {
          'id': 42,
          'kind': 'post',
          'type': 'text',
          'title': 'Обычный пост',
          'status': 'published',
          'created_at': '2026-01-01T00:00:00.000Z',
          'user_id': 9,
        },
      ],
      'has_more': false,
    });

    expect(response.items, hasLength(1));
    expect(response.items.single.id, 42);
    expect(response.items.single.title, 'Обычный пост');
  });
}
