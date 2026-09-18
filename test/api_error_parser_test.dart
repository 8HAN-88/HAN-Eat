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

  test('localizeKnownEnglishDetail maps likes donations and miniapps', () {
    expect(parseApiErrorMessage('Post already liked'), 'Пост уже в избранном');
    expect(
      parseApiErrorMessage('Cannot donate to yourself'),
      'Нельзя отправить донат себе',
    );
    expect(
      parseApiErrorMessage('Mini app is not approved yet'),
      'Мини-приложение ещё не одобрено',
    );
    expect(
        parseApiErrorMessage('Rate limit exceeded'), 'Слишком много запросов');
  });

  test('localizeKnownEnglishDetail maps report and publish leftovers', () {
    expect(
      parseApiErrorMessage('Cannot report your own post'),
      'Нельзя пожаловаться на свой пост',
    );
    expect(
      parseApiErrorMessage('Post already saved'),
      'Пост уже сохранён',
    );
    expect(
      parseApiErrorMessage('Требуется тариф Creator или Pro'),
      'Доступно с подпиской уровня 16',
    );
    expect(
      parseApiErrorMessage('Only published posts can be promoted'),
      'Продвигать можно только опубликованные посты',
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

  test(
      'localizeKnownEnglishDetail maps stickers stories gifs and miniapps leftovers',
      () {
    expect(parseApiErrorMessage('pack_not_found'), 'Набор стикеров не найден');
    expect(parseApiErrorMessage('Story not found'), 'История не найдена');
    expect(
      parseApiErrorMessage('GIF search is temporarily unavailable'),
      'Поиск гифок временно недоступен',
    );
    expect(
      parseApiErrorMessage('Notification not found'),
      'Уведомление не найдено',
    );
    expect(parseApiErrorMessage('Bot token is missing'), 'Нет токена бота');
    expect(
      parseApiErrorMessage('Already refunded'),
      'Возврат уже выполнен',
    );
    expect(
      parseApiErrorMessage({
        'code': 'MINIAPP_RATE_LIMIT_EXCEEDED',
        'message': 'Too many mini app requests. Please try again later.',
      }),
      'Слишком много запросов к мини-приложению. Подождите немного.',
    );
  });

  test(
      'localizeKnownEnglishDetail maps leftover Creator analytics and previews',
      () {
    expect(
      parseApiErrorMessage('Аналитика доступна с тарифом Creator или Pro'),
      'Аналитика доступна с подпиской уровня 16',
    );
    expect(
      parseApiErrorMessage('Post not found or access denied'),
      'Пост не найден или нет доступа',
    );
    expect(
      parseApiErrorMessage('Could not fetch preview'),
      'Не удалось получить предпросмотр',
    );
    expect(parseApiErrorMessage('Group not found'), 'Группа не найдена');
  });

  test('localizeKnownEnglishDetail maps auth subscription and repost leftovers',
      () {
    expect(
      parseApiErrorMessage('Incorrect email or password'),
      'Неверный email или пароль',
    );
    expect(parseApiErrorMessage('Account suspended'), 'Аккаунт заблокирован');
    expect(
      parseApiErrorMessage('Your cancellation request has been submitted.'),
      'Запрос на отмену отправлен',
    );
    expect(parseApiErrorMessage('User profile is private'), 'Профиль закрытый');
    expect(
      parseApiErrorMessage('Post already reposted'),
      'Вы уже репостнули этот пост',
    );
    expect(
      parseApiErrorMessage('Cannot repost your own post'),
      'Нельзя репостнуть свой пост',
    );
  });

  test(
      'localizeKnownEnglishDetail maps paid gifts giveaways and search leftovers',
      () {
    expect(parseApiErrorMessage('Gift not found'), 'Подарок не найден');
    expect(
      parseApiErrorMessage('Creator cannot join own giveaway'),
      'Нельзя участвовать в своём розыгрыше',
    );
    expect(parseApiErrorMessage('empty_text'), 'Введите текст для ассистента');
    expect(
      parseApiErrorMessage('q must be at least 2 characters'),
      'В запросе нужно минимум 2 символа',
    );
    expect(parseApiErrorMessage('Video not found'), 'Видео не найдено');
    expect(parseApiErrorMessage('Call not found'), 'Звонок не найден');
    expect(
      parseApiErrorMessage('Cannot call this user'),
      'Этому пользователю нельзя позвонить',
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
