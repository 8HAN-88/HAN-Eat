import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/search/presentation/search_screen.dart';

void main() {
  test('exact slug or name pins a channel above people', () {
    expect(
      channelMatchesSearchExactly('han', slug: 'han', name: 'HAN'),
      isTrue,
    );
    expect(
      channelMatchesSearchExactly('HAN', slug: 'han', name: 'HAN'),
      isTrue,
    );
    expect(
      channelMatchesSearchExactly('hanan', slug: 'han', name: 'HAN'),
      isFalse,
    );
    expect(
      channelMatchesSearchExactly('admin', slug: 'han', name: 'HAN'),
      isFalse,
    );
  });
}
