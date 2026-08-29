import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/feed/application/feed_tab_layout.dart';

void main() {
  test('home feed is a single subscriptions tab plus reels', () {
    expect(FeedTabLayout.labels, ['Лента', 'Рилсы']);
    expect(FeedTabLayout.count, 2);
    expect(FeedTabLayout.isReels(FeedTabLayout.reels), isTrue);
    expect(FeedTabLayout.isReels(FeedTabLayout.home), isFalse);
  });

  test('migrates old three-tab index', () {
    expect(FeedTabLayout.migrateStoredIndex(0, isV2: false), FeedTabLayout.home);
    expect(FeedTabLayout.migrateStoredIndex(1, isV2: false), FeedTabLayout.home);
    expect(FeedTabLayout.migrateStoredIndex(2, isV2: false), FeedTabLayout.reels);
    expect(FeedTabLayout.migrateStoredIndex(1, isV2: true), FeedTabLayout.reels);
  });
}
