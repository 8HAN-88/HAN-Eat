import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/network/feed_load_helper.dart';

void main() {
  group('FeedLoadHelper', () {
    test('isNetworkError detects timeout', () {
      expect(FeedLoadHelper.isNetworkError(TimeoutException('x')), isTrue);
    });

    test('feedLoadErrorMessage for timeout mentions server', () {
      final msg = FeedLoadHelper.feedLoadErrorMessage(TimeoutException('x'));
      expect(msg, contains('Сервер недоступен'));
      expect(msg, contains('обновите'));
    });

    test('cacheSnackMessage for session', () {
      expect(
        FeedLoadHelper.cacheSnackMessage(Exception('Сессия истекла')),
        contains('Войдите'),
      );
    });
  });
}
