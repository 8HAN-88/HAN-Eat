import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/feed/presentation/feed_section_tabs.dart';

void main() {
  test('feed tabs keep full Russian labels', () {
    expect(FeedSectionTabs.labels, ['Лента', 'Рилсы']);
    for (final label in FeedSectionTabs.labels) {
      expect(label.contains('…'), isFalse);
      expect(label.length, greaterThan(3));
    }
  });
}
