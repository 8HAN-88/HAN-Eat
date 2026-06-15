import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/app/invalid_link_screen.dart';
import 'package:han_eat/core/network/feed_load_helper.dart';
import 'package:han_eat/services/api_service.dart';
import 'package:han_eat/services/auth_service.dart';

void main() {
  group('parseRoutePositiveId', () {
    test('accepts positive integers', () {
      expect(parseRoutePositiveId('42'), 42);
      expect(parseRoutePositiveId('1'), 1);
    });

    test('rejects invalid ids', () {
      expect(parseRoutePositiveId(null), isNull);
      expect(parseRoutePositiveId(''), isNull);
      expect(parseRoutePositiveId('abc'), isNull);
      expect(parseRoutePositiveId('0'), isNull);
      expect(parseRoutePositiveId('-1'), isNull);
    });
  });

  group('FeedLoadHelper.isSessionError', () {
    test('network errors are not session errors', () {
      expect(
        FeedLoadHelper.isSessionError(
          AuthException('Сервер недоступен. Проверьте подключение к серверу.'),
        ),
        isFalse,
      );
      expect(
        FeedLoadHelper.isSessionError(Exception('Connection refused')),
        isFalse,
      );
    });

    test('expired session is detected', () {
      expect(
        FeedLoadHelper.isSessionError(
          AuthException('Сессия истекла. Войдите снова.'),
        ),
        isTrue,
      );
      expect(
        FeedLoadHelper.isSessionError(
          const HanLoginRequiredException('Войдите в аккаунт'),
        ),
        isTrue,
      );
    });
  });
}
