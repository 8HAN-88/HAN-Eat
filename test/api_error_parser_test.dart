import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/api_error_parser.dart';

void main() {
  test('parseApiErrorMessage maps CONTENT_BLOCKED', () {
    expect(
      parseApiErrorMessage({'code': 'CONTENT_BLOCKED'}),
      contains('модерацию'),
    );
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
