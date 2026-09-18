import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/api_error_parser.dart';

void main() {
  test('parseApiErrorMessage maps CONTENT_BLOCKED', () {
    expect(
      parseApiErrorMessage({'code': 'CONTENT_BLOCKED'}),
      contains('модерацию'),
    );
  });

  test('userVisibleError localizes rate-limit English detail', () {
    expect(
      userVisibleError(
        const ApiClientException(
          message: 'Too many requests. Please try again later.',
          statusCode: 429,
          code: 'RATE_LIMIT_EXCEEDED',
        ),
      ),
      'Слишком много запросов. Подождите немного.',
    );
    expect(
      parseApiErrorMessage('Too many requests. Please try again later.'),
      'Слишком много запросов. Подождите немного.',
    );
  });

  test('isTransientRateLimitError detects 429', () {
    expect(
      isTransientRateLimitError(
        const ApiClientException(message: 'x', statusCode: 429),
      ),
      isTrue,
    );
    expect(isTransientRateLimitError(Exception('network')), isFalse);
  });

  test('userVisibleError uses ApiClientException message', () {
    expect(
      userVisibleError(
        const ApiClientException(message: 'Нельзя репостнуть свой пост'),
      ),
      'Нельзя репостнуть свой пост',
    );
  });

  test('userVisibleError maps Not authenticated', () {
    expect(
      userVisibleError(Exception('Not authenticated')),
      'Войдите в аккаунт',
    );
  });

  test('localizeKnownEnglishDetail maps channel and support leftovers', () {
    expect(
      parseApiErrorMessage('Already a member of this channel'),
      'Вы уже в канале',
    );
    expect(
      parseApiErrorMessage('Cannot access saved posts'),
      'Нет доступа к сохранённым постам',
    );
    expect(
      userVisibleError(Exception('Failed to load receipt')),
      'Не удалось загрузить чек',
    );
    expect(
      localizeKnownEnglishDetail('Request processed successfully'),
      'Обращение обработано',
    );
  });

  test('parseApiErrorMessage maps FEATURE_REMOVED and payment English', () {
    expect(
      parseApiErrorMessage({'code': 'FEATURE_REMOVED'}),
      'Этот раздел удалён. HanWe — мессенджер.',
    );
    expect(
      parseApiErrorMessage('T-Bank unavailable'),
      'Оплата подписок временно недоступна',
    );
    expect(
      parseApiErrorMessage(
          'Kitchen features were removed. HanWe is a messenger.'),
      'Этот раздел удалён. HanWe — мессенджер.',
    );
  });

  test('userVisibleError maps FlutterWebRTC MissingPluginException', () {
    expect(
      userVisibleError(
        Exception(
          'MissingPluginException(No implementation found for method initialize on channel FlutterWebRTC.Method)',
        ),
      ),
      contains('браузере'),
    );
  });

  test('userVisibleAuthError prefers auth message for 401', () {
    expect(
      userVisibleAuthError(
        const ApiClientException(message: 'x', statusCode: 401),
        authFallback: 'Войдите, чтобы поставить лайк',
      ),
      'Войдите, чтобы поставить лайк',
    );
    expect(
      userVisibleAuthError(
        Exception('network'),
        fallback: 'Сеть недоступна',
      ),
      'network',
    );
  });
}
