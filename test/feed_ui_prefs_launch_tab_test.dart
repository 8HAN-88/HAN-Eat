import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/feed_ui_prefs.dart';

void main() {
  test('web cold start never opens the reels tab', () {
    expect(FeedUiPrefs.launchTabIndex(2, isWeb: true), 1);
    expect(FeedUiPrefs.launchTabIndex(1, isWeb: true), 1);
    expect(FeedUiPrefs.launchTabIndex(0, isWeb: true), 0);
  });

  test('native keeps the saved reels tab', () {
    expect(FeedUiPrefs.launchTabIndex(2, isWeb: false), 2);
  });
}
