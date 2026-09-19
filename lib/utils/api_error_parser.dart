import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Разбор ошибок FastAPI (`detail` как строка, объект или список).
class ApiClientException implements Exception {
  const ApiClientException({
    required this.message,
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
    this.details,
  });

  final int? statusCode;
  final String? code;
  final int? retryAfterSeconds;
  final String message;
  final Map<String, dynamic>? details;

  bool get isContentBlocked => code == 'CONTENT_BLOCKED';
  bool get isRateLimited => statusCode == 429 || code == 'RATE_LIMIT_EXCEEDED';

  @override
  String toString() => message;
}

const _knownEnglishDetails = <String, String>{
  'Authentication required': 'Войдите в аккаунт',
  'Membership pending approval': 'Заявка на вступление ещё на рассмотрении',
  'Channel is private': 'Канал закрытый',
  'Channel with this slug already exists': 'Канал с таким адресом уже есть',
  'Channel not found': 'Канал не найден',
  'Not a member of this channel': 'Вы не участник канала',
  'Already a member of this channel': 'Вы уже в канале',
  'Owner or admin cannot leave channel. Transfer rights or delete channel.':
      'Владелец или админ не может выйти. Передайте права или удалите канал.',
  'Join request not found': 'Заявка не найдена',
  'Post not found': 'Пост не найден',
  'Member not found': 'Участник не найден',
  'Cannot change owner role': 'Роль владельца менять нельзя',
  'Invalid role. Must be: admin, moderator, or member':
      'Неверная роль. Допустимо: админ, модератор или участник',
  'Cannot remove channel owner': 'Нельзя удалить владельца канала',
  'Only channel owner can delete channel':
      'Удалить канал может только владелец',
  'Ticket not found': 'Обращение не найдено',
  'Ticket already resolved or closed': 'Обращение уже закрыто',
  'Failed to cancel subscription': 'Не удалось отменить подписку',
  'Subscription not found': 'Подписка не найдена',
  'Request processed successfully': 'Обращение обработано',
  'Ticket resolved successfully': 'Обращение закрыто',
  'Cannot access saved posts': 'Нет доступа к сохранённым постам',
  'Failed to load receipt': 'Не удалось загрузить чек',
  'Could not open receipt URL': 'Не удалось открыть чек',
  'Failed to request refund': 'Не удалось отправить запрос на возврат',
  'Refund request already submitted': 'Запрос на возврат уже отправлен',
  'Refund is not available for this payment':
      'Возврат для этого платежа недоступен',
  'Payment not found': 'Платёж не найден',
  'Post already saved': 'Пост уже сохранён',
  'Post not saved': 'Пост не был сохранён',
  'Cannot report your own post': 'Нельзя пожаловаться на свой пост',
  'Cannot report your own comment': 'Нельзя пожаловаться на свой комментарий',
  'Cannot report your own channel': 'Нельзя пожаловаться на свой канал',
  'Cannot report yourself': 'Нельзя пожаловаться на себя',
  'Cannot report your own message': 'Нельзя пожаловаться на своё сообщение',
  'Comment not found': 'Комментарий не найден',
  'User not found': 'Пользователь не найден',
  'Message not found': 'Сообщение не найдено',
  'Access denied': 'Нет доступа',
  'Not your post': 'Это не ваш пост',
  'Not allowed': 'Нет доступа',
  'Post is private': 'Пост закрытый',
  'Only published posts can be promoted':
      'Продвигать можно только опубликованные посты',
  'Only published posts can be pinned':
      'Закреплять можно только опубликованные посты',
  'Only channel posts can be pinned': 'Закреплять можно только посты канала',
  'scheduled_publish_at must be in the future':
      'Время публикации должно быть в будущем',
  'Scheduled post not found': 'Отложенный пост не найден',
  'Требуется тариф Creator или Pro': 'Доступно с подпиской уровня 16',
  'Invalid date_from format. Use YYYY-MM-DD':
      'Неверный формат даты. Используйте ГГГГ-ММ-ДД',
  'Invalid date_to format. Use YYYY-MM-DD':
      'Неверный формат даты. Используйте ГГГГ-ММ-ДД',
  'sort_by must be one of: relevance, date, popularity':
      'Неверная сортировка. Допустимо: по релевантности, по дате или по популярности.',
  'Сортировка: relevance, date или popularity':
      'Неверная сортировка. Допустимо: по релевантности, по дате или по популярности.',
  'Too many uploads. Please try again later.':
      'Слишком много загрузок. Попробуйте позже.',
  'User data validation failed': 'Данные профиля не прошли проверку',
  'Internal server error during login': 'Не удалось войти. Попробуйте позже.',
  'Google authentication failed':
      'Не удалось войти через Google. Попробуйте снова.',
  'Yandex authentication failed':
      'Не удалось войти через Яндекс. Попробуйте снова.',
  'Suggestions error': 'Не удалось загрузить подсказки поиска',
  'Failed to create channel': 'Не удалось создать канал. Попробуйте позже.',
  'Dead-letter backlog is high': 'Высокая очередь недоставленных вебхуков',
  'Bots auto-disabled due to webhook failures':
      'Боты отключены из-за ошибок вебхуков',
  'Webhook fail volume is high in last hour':
      'Много ошибок вебхуков за последний час',
  'Webhook fail-rate is high in last hour':
      'Высокая доля ошибок вебхуков за последний час',
  'Dropped deliveries reached alert threshold':
      'Слишком много отброшенных доставок',
  'Per-bot webhook rate limit drops are high':
      'Слишком много отбросов из-за лимита бота',
  'Authentication required for following_only search':
      'Войдите в аккаунт, чтобы искать только подписки',
  'Text or rating is required': 'Нужен текст или оценка',
  'You can only delete your own comments':
      'Можно удалить только свой комментарий',
  'Failed to load refund queue': 'Не удалось загрузить очередь возвратов',
  'Failed to process refund': 'Не удалось обработать возврат',
  'Failed to reject refund': 'Не удалось отклонить возврат',
  'Could not launch checkout URL': 'Не удалось открыть оплату',
  'Poll not found': 'Опрос не найден',
  'URL is required': 'Нужна ссылка',
  'Post already liked': 'Пост уже в избранном',
  'Like not found': 'Лайк не найден',
  'Recipient not found': 'Получатель не найден',
  'Cannot donate to yourself': 'Нельзя отправить донат себе',
  'Invalid channel': 'Неверный канал',
  'Invalid post': 'Неверный пост',
  'Rate limit exceeded': 'Слишком много запросов',
  'Bot not found': 'Бот не найден',
  'Webhook URL is required': 'Укажите адрес вебхука',
  'Webhook is not configured or disabled': 'Вебхук не настроен или выключен',
  'Mini app is not approved yet': 'Мини-приложение ещё не одобрено',
  'Mini app not found': 'Мини-приложение не найдено',
  'URL must start with http:// or https://':
      'Адрес должен начинаться с http:// или https://',
  'Only https URLs are allowed in production':
      'В продакшене разрешён только https',
  'Command already exists': 'Такая команда уже есть',
  'Command not found': 'Команда не найдена',
  'pack_not_found': 'Набор стикеров не найден',
  'sticker_not_found': 'Стикер не найден',
  'missing_sticker': 'Нужен стикер',
  'empty_patch': 'Нет изменений',
  'invalid_title': 'Неверное название',
  'missing_media': 'Нужно медиа',
  'invalid_sticker_type': 'Неверный тип стикера',
  'Story not found': 'История не найдена',
  'Invalid visibility': 'Неверная видимость',
  'Only the author can see viewers': 'Просмотры видит только автор',
  'Cannot react to your own story': 'Нельзя ставить реакцию на свою историю',
  'Invalid emoji': 'Неверный эмодзи',
  'Notification not found': 'Уведомление не найдено',
  'GIF search is temporarily unavailable': 'Поиск гифок временно недоступен',
  'GIF catalog is temporarily unavailable': 'Каталог гифок временно недоступен',
  'Bot token is missing': 'Нет токена бота',
  'Bot is not in this chat': 'Бота нет в этом чате',
  'short_name must be alphanumeric with _ or -':
      'Короткое имя: только буквы, цифры, _ или -',
  'Mini app short_name already exists for this bot':
      'Такое короткое имя уже есть у этого бота',
  'URL credentials are not allowed': 'Учётные данные в ссылке запрещены',
  'URL fragments are not allowed': 'Фрагмент ссылки запрещён',
  'Local/private hosts are not allowed':
      'Локальные и закрытые адреса запрещены',
  'URL host is not allowed': 'Этот хост не разрешён',
  'bad_miniapp_category': 'Неверная категория мини-приложения',
  'data is required': 'Нужны данные',
  'data too long': 'Слишком много данных',
  'init_data must be valid JSON': 'init_data должен быть корректным JSON',
  'init_data must be an object': 'init_data должен быть объектом',
  'init_data hash is required': 'Нужна подпись init_data',
  'init_data auth_date is invalid': 'Неверная дата init_data',
  'init_data auth_date is in the future': 'Дата init_data в будущем',
  'init_data has expired': 'Срок init_data истёк',
  'init_data miniapp_id mismatch': 'init_data не совпадает с мини-приложением',
  'init_data bot_id mismatch': 'init_data не совпадает с ботом',
  'init_data user is missing': 'В init_data нет пользователя',
  'init_data user.id is invalid': 'Неверный user.id в init_data',
  'Invalid init_data signature': 'Неверная подпись init_data',
  'Already refunded': 'Возврат уже выполнен',
  'Failed to create payment session': 'Не удалось создать сессию оплаты',
  'Failed to create checkout session': 'Не удалось создать сессию оплаты',
  'Failed to create stars checkout': 'Не удалось создать оплату звёзд',
  'Failed to load subscription prices': 'Не удалось загрузить цены',
  'Failed to load payment history': 'Не удалось загрузить историю оплат',
  'Unknown stars package': 'Неизвестный пакет звёзд',
  'Too many mini app requests. Please try again later.':
      'Слишком много запросов к мини-приложению. Подождите немного.',
  'Incorrect email or password': 'Неверная почта или пароль',
  'Email already registered': 'Почта уже занята',
  'Email уже занят': 'Почта уже занята',
  'Неверный email или пароль': 'Неверная почта или пароль',
  'Username already taken': 'Это имя уже занято',
  'Account deleted': 'Аккаунт удалён',
  'Account suspended': 'Аккаунт заблокирован',
  'Invalid refresh token': 'Неверный токен обновления',
  'Invalid token payload': 'Неверные данные токена',
  'Invalid authentication credentials': 'Неверные данные входа',
  'Session not found': 'Сессия не найдена',
  'Session revoked': 'Сессия отозвана',
  'Two-factor authentication is already enabled':
      'Двухфакторная защита уже включена',
  'Two-factor authentication is not enabled':
      'Двухфакторная защита не включена',
  'Invalid authenticator code': 'Неверный код из приложения',
  'Incorrect password': 'Неверный пароль',
  'Invalid or expired 2FA pending token': 'Код входа устарел. Войдите снова',
  'No active subscription found': 'Активная подписка не найдена',
  'You already have an open request to cancel subscription.':
      'Запрос на отмену уже отправлен',
  'Your cancellation request has been submitted.': 'Запрос на отмену отправлен',
  'User profile is private': 'Профиль закрытый',
  'Cannot add yourself': 'Нельзя добавить себя',
  'Close friend not found': 'Близкий друг не найден',
  'Post already reposted': 'Вы уже репостнули этот пост',
  'Cannot repost your own post': 'Нельзя репостнуть свой пост',
  'Repost not found': 'Репост не найден',
  'Plan must be \'monthly\' or \'yearly\'': 'Выберите период: месяц или год',
  'Product must be \'ai\', \'creator\', or \'pro\'': 'Неверный тариф',
  'Trial is only available for \'ai\' or \'pro\'':
      'Пробный период доступен для уровней 9 и 18',
  'Trial is not available for this account':
      'Пробный период для этого аккаунта недоступен',
  'Admin access required': 'Нужны права администратора',
  'Moderator or admin access required': 'Нужны права модератора',
  'Приватные каналы доступны с тарифом Creator или Pro':
      'Приватные каналы доступны с подпиской уровня 16',
  'Оформление канала доступно с тарифом Creator или Pro':
      'Оформление канала доступно с подпиской уровня 16',
  'Аналитика доступна с тарифом Creator или Pro':
      'Аналитика доступна с подпиской уровня 16',
  'Event type not allowed': 'Этот тип события недоступен',
  'Post not found or access denied': 'Пост не найден или нет доступа',
  'Could not fetch preview': 'Не удалось получить предпросмотр',
  'No preview available': 'Предпросмотр недоступен',
  'Only http/https URLs are allowed': 'Разрешены только ссылки http/https',
  'Invalid URL': 'Неверная ссылка',
  'Blocked host': 'Этот адрес недоступен',
  'Could not resolve host': 'Не удалось найти этот адрес',
  'Empty upload body': 'Файл пустой',
  'Invalid file path': 'Неверный путь к файлу',
  'File not found': 'Файл не найден',
  'Group not found': 'Группа не найдена',
  'Gift not found': 'Подарок не найден',
  'Giveaway not found': 'Розыгрыш не найден',
  'Invoice not found': 'Счёт не найден',
  'Invoice already paid': 'Счёт уже оплачен',
  'Invoice expired': 'Срок счёта истёк',
  'Cannot pay own invoice': 'Нельзя оплатить свой счёт',
  'Creator cannot join own giveaway': 'Нельзя участвовать в своём розыгрыше',
  'Join the channel to enter the giveaway':
      'Вступите в канал, чтобы участвовать',
  'Channel already has an active giveaway':
      'В канале уже есть активный розыгрыш',
  'empty_text': 'Введите текст для ассистента',
  'unsupported_emoji': 'Эта реакция недоступна',
  'Video not found': 'Видео не найдено',
  'Bot not found or access denied': 'Бот не найден или нет доступа',
  'You are not a member of this chat': 'Вы не участник этого чата',
  'Conversation not found': 'Чат не найден',
  'Invalid date format. Use YYYY-MM-DD':
      'Неверный формат даты. Используйте ГГГГ-ММ-ДД',
  'q must be at least 2 characters': 'В запросе нужно минимум 2 символа',
  'Provide q (min 2 chars) and/or date_from/date_to':
      'Укажите запрос (от 2 символов) или даты',
  'Cannot ban admin': 'Нельзя заблокировать администратора',
  'Moderation item not found': 'Элемент модерации не найден',
  'Item already moderated': 'Элемент уже проверен',
  'Amount must be positive': 'Сумма должна быть больше нуля',
  'Gift is not for sale': 'Подарок не продаётся',
  'Cannot buy your own gift': 'Нельзя купить свой подарок',
  'Call not found': 'Звонок не найден',
  'Calls only supported in direct chats':
      'Звонки доступны только в личных чатах',
  'Cannot call this user': 'Этому пользователю нельзя позвонить',
  'Call is not ringing': 'Звонок уже не идёт',
  'Call is not active': 'Звонок не активен',
  'Yandex OAuth is not configured': 'Вход через Яндекс не настроен',
  'Yandex account has no email': 'В аккаунте Яндекса нет email',
  'Saved chat failed': 'Не удалось открыть избранное',
  'Folder not found': 'Папка не найдена',
  'Cannot chat with yourself': 'Нельзя написать себе',
  'User blocked': 'Пользователь в чёрном списке',
  'Chat create failed': 'Не удалось создать чат',
  'Group create failed': 'Не удалось создать группу',
  'Invite link error': 'Не удалось создать ссылку-приглашение',
  'Invite link not found': 'Ссылка-приглашение не найдена',
  'Join failed': 'Не удалось вступить',
  'Scheduled message not found': 'Отложенное сообщение не найдено',
  'Only sender can update': 'Обновить может только отправитель',
  'Only sender can stop': 'Остановить может только отправитель',
  'Invalid scope': 'Неверная область удаления',
  'Not a group chat': 'Это не группа',
  'Topic not found': 'Тема не найдена',
  'Ban not found': 'Блокировка не найдена',
  'Request not found': 'Заявка не найдена',
  'Contact not found': 'Контакт не найден',
  'Content is protected': 'Контент защищён от пересылки',
  'Message is too old to delete for everyone':
      'Сообщение слишком старое, чтобы удалить у всех',
  'Too many chat actions. Please try again later.':
      'Слишком много действий в чате. Подождите немного.',
  'Cannot block yourself': 'Нельзя заблокировать себя',
  'Block not found': 'Блокировка не найдена',
  'slug already exists': 'Такая функция уже есть',
  'key required': 'Нужен ключ блока',
  'cannot_ban_self': 'Нельзя заблокировать себя',
  'cannot_ban_creator': 'Нельзя заблокировать создателя',
  'cannot_ban_admin': 'Нельзя заблокировать администратора',
  'cannot_restrict_self': 'Нельзя ограничить себя',
  'cannot_restrict_creator': 'Нельзя ограничить создателя',
  'cannot_restrict_admin': 'Нельзя ограничить администратора',
  'cannot_change_self_role': 'Нельзя изменить свою роль',
  'already_reviewed': 'Заявка уже рассмотрена',
  'group_member_banned': 'Пользователь заблокирован в группе',
  'empty_title': 'Название не может быть пустым',
  'empty_draft': 'Черновик пустой',
  'callback_not_found': 'Кнопка не найдена',
  'not_live_location': 'Это не живая геопозиция',
  'bad_bubble_accent': 'Неверный цвет пузырей',
  'target_not_admin': 'Пользователь не модератор',
  'invalid_restriction_until': 'Неверная дата ограничения',
  'invalid_ban_until': 'Неверная дата блокировки',
  'not_a_forum': 'В этой группе темы выключены',
  'cannot_close_general': 'Общую тему закрыть нельзя',
  'Invalid post ID': 'Неверный пост',
  'Invalid poll response': 'Неверный ответ опроса',
  'no video url': 'Нет ссылки на видео',
  'video init failed': 'Не удалось запустить видео',
  'Authentication failed. Please log in again.': 'Войдите в аккаунт',
  'Not authenticated. Please log in first.': 'Войдите в аккаунт',
  'net::ERR_NAME_NOT_RESOLVED':
      'Нет подключения. Проверьте интернет и попробуйте снова.',
  'net::ERR_INTERNET_DISCONNECTED':
      'Нет подключения. Проверьте интернет и попробуйте снова.',
  'net::ERR_CONNECTION_TIMED_OUT': 'Сервер не отвечает. Попробуйте ещё раз.',
  'net::ERR_CONNECTION_REFUSED': 'Сервер недоступен. Попробуйте ещё раз.',
};

String? localizeKnownEnglishDetail(String detail) =>
    _knownEnglishDetails[detail];

String parseApiErrorMessage(
  dynamic detail, {
  String fallback = 'Произошла ошибка',
}) {
  if (detail == null) return fallback;
  if (detail is String) {
    final known = localizeKnownEnglishDetail(detail);
    if (known != null) return known;
    return switch (detail) {
      'network_error' =>
        'Нет подключения к серверу. Проверьте интернет и попробуйте снова.',
      'timeout' => 'Превышено время ожидания ответа от сервера',
      'offline' => 'Войдите в аккаунт',
      'group_slow_mode' =>
        'Слишком часто. В этом чате включен медленный режим, подождите немного.',
      'group_flood_limited' =>
        'Превышен лимит сообщений в минуту. Подождите и попробуйте снова.',
      'paid_media_locked' => 'Сначала откройте платное медиа, чтобы переслать',
      'T-Bank unavailable' ||
      'YooKassa unavailable' ||
      'Payments unavailable' ||
      'Payment service (T-Bank) is not available' =>
        'Оплата подписок временно недоступна',
      _ => () {
          final lower = detail.toLowerCase();
          if (lower.contains('too many requests') ||
              detail == 'RATE_LIMIT_EXCEEDED') {
            return 'Слишком много запросов. Подождите немного.';
          }
          if (lower.contains('kitchen features were removed')) {
            return 'Этот раздел удалён. HanWe — мессенджер.';
          }
          if (lower.contains('level must be')) {
            return 'Выберите уровень от 1 до 79';
          }
          if (lower.contains('please log in') ||
              lower.contains('not authenticated')) {
            return 'Войдите в аккаунт';
          }
          if (lower.startsWith('failed to')) {
            return 'Не удалось выполнить действие. Попробуйте ещё раз.';
          }
          if (lower.contains('payment is not available')) {
            return 'Оплата подписок временно недоступна';
          }
          return detail;
        }(),
    };
  }
  if (detail is Map) {
    final msg = detail['message'] as String?;
    if (msg != null && msg.isNotEmpty) {
      return localizeKnownEnglishDetail(msg) ?? msg;
    }
    final code = detail['code'] as String?;
    if (code == 'STARS_REQUIRED') {
      return 'Недостаточно звёзд';
    }
    if (code == 'group_paid_required') {
      final price = detail['monthly_price_stars'];
      if (price is num && price > 0) {
        return 'Чтобы вступить, оформите подписку за $price ★ / мес';
      }
      return 'Чтобы вступить, оформите платную подписку на группу';
    }
    if (code == 'paid_media_locked') {
      return 'Сначала откройте платное медиа, чтобы переслать';
    }
    if (code == 'CONTENT_BLOCKED') {
      return 'Публикация не прошла модерацию и не может быть опубликована';
    }
    if (code == 'PAYMENTS_UNAVAILABLE') {
      return 'Оплата подписок временно недоступна';
    }
    if (code == 'MINIAPP_RATE_LIMIT_EXCEEDED') {
      return 'Слишком много запросов к мини-приложению. Подождите немного.';
    }
    if (code == 'CHAT_RATE_LIMIT_EXCEEDED') {
      return 'Слишком много действий в чате. Подождите немного.';
    }
    if (code == 'UPLOAD_RATE_LIMIT_EXCEEDED') {
      return 'Слишком много загрузок. Попробуйте позже.';
    }
    if (code == 'LEGAL_CONSENT_REQUIRED') {
      return 'Примите документы перед оплатой';
    }
    if (code == 'FEATURE_REMOVED' || code == 'kitchen_retired') {
      return 'Этот раздел удалён. HanWe — мессенджер.';
    }
    if (code == 'INVALID_FLEX_LEVEL') {
      return 'Выберите уровень от 1 до 79';
    }
    if (code == 'group_slow_mode') {
      final retry = parseApiRetryAfterSeconds(detail);
      if (retry != null && retry > 0) {
        return 'Слишком часто. Подождите $retryс и попробуйте снова.';
      }
      return 'Слишком часто. В этом чате включен медленный режим, подождите немного.';
    }
    if (code == 'group_flood_limited') {
      final retry = parseApiRetryAfterSeconds(detail);
      if (retry != null && retry > 0) {
        return 'Лимит сообщений в минуту превышен. Подождите $retryс.';
      }
      return 'Превышен лимит сообщений в минуту. Подождите и попробуйте снова.';
    }
    return fallback;
  }
  if (detail is List && detail.isNotEmpty) {
    final first = detail.first;
    if (first is Map) {
      final msg = first['msg'] as String? ?? first['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return detail.first.toString();
  }
  return fallback;
}

String? parseApiErrorCode(dynamic detail) {
  if (detail is Map) {
    return detail['code'] as String?;
  }
  return null;
}

int? parseApiRetryAfterSeconds(dynamic detail) {
  if (detail is! Map) return null;
  final raw = detail['retry_after_seconds'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

ApiClientException apiExceptionFromResponse(
  int statusCode,
  Map<String, dynamic> body, {
  String fallback = 'Произошла ошибка',
}) {
  final detail = body['detail'];
  return ApiClientException(
    statusCode: statusCode,
    code: parseApiErrorCode(detail),
    retryAfterSeconds: parseApiRetryAfterSeconds(detail),
    message: parseApiErrorMessage(detail, fallback: fallback),
    details: detail is Map<String, dynamic>
        ? Map<String, dynamic>.from(detail)
        : (detail is Map ? Map<String, dynamic>.from(detail) : null),
  );
}

/// Сообщение по HTTP-ответу API (для сервисов без ApiClientException).
ApiClientException apiExceptionFromHttpResponse(
  int statusCode,
  String body, {
  String fallback = 'Произошла ошибка',
}) {
  if (statusCode == 503 && body.contains('offline')) {
    return const ApiClientException(
      statusCode: 503,
      message: 'Войдите в аккаунт',
    );
  }
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map<String, dynamic>) {
      return apiExceptionFromResponse(statusCode, parsed, fallback: fallback);
    }
  } catch (_) {}
  return _httpStatusMessage(statusCode, fallback: fallback);
}

ApiClientException _httpStatusMessage(
  int statusCode, {
  String fallback = 'Произошла ошибка',
}) {
  final message = switch (statusCode) {
    401 => 'Войдите в аккаунт',
    403 => 'Нет доступа',
    404 => 'Не найдено',
    429 => 'Слишком много запросов. Подождите немного.',
    502 || 503 || 504 => 'Сервер временно недоступен',
    _ => fallback,
  };
  return ApiClientException(statusCode: statusCode, message: message);
}

bool _isNetworkError(Object e) {
  if (e is SocketException) return true;
  if (e is HttpException) return true;
  if (e is HandshakeException) return true;
  final s = e.toString().toLowerCase();
  return s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('no route to host') ||
      s.contains('tlsv1_alert') ||
      s.contains('handshakeexception');
}

bool isTransientRateLimitError(Object? e) {
  if (e == null) return false;
  if (e is ApiClientException) return e.isRateLimited;
  final lower = e.toString().toLowerCase();
  return lower.contains('too many requests') ||
      lower.contains('rate_limit') ||
      lower.contains('429');
}

/// Текст ошибки для SnackBar / диалогов.
String userVisibleError(Object e, {String fallback = 'Произошла ошибка'}) {
  if (isTransientRateLimitError(e)) {
    return 'Слишком много запросов. Подождите немного.';
  }
  if (e is ApiClientException) return e.message;
  if (e is TimeoutException) {
    return 'Превышено время ожидания ответа от сервера';
  }
  if (_isNetworkError(e)) {
    return 'Нет подключения к серверу. Проверьте интернет и попробуйте снова.';
  }
  final raw = e.toString().replaceAll('Exception: ', '').trim();
  if (raw.isEmpty) return fallback;
  final known = localizeKnownEnglishDetail(raw);
  if (known != null) return known;
  if (raw == 'Not authenticated' ||
      raw.toLowerCase().contains('please log in')) {
    return 'Войдите в аккаунт';
  }
  final lower = raw.toLowerCase();
  if (lower.contains('kitchen features were removed')) {
    return 'Этот раздел удалён. HanWe — мессенджер.';
  }
  if ((lower.contains('t-bank') && lower.contains('unavailable')) ||
      (lower.contains('yookassa') && lower.contains('unavailable')) ||
      lower.contains('payments unavailable') ||
      lower.contains('payment is not available')) {
    return 'Оплата подписок временно недоступна';
  }
  if (lower.contains('level must be')) {
    return 'Выберите уровень от 1 до 79';
  }
  if (lower.startsWith('failed to')) {
    if (lower.contains('create channel')) {
      return 'Не удалось создать канал. Попробуйте позже.';
    }
    return 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }
  if (lower.startsWith('api error')) {
    return 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }
  if (lower.startsWith('google authentication failed')) {
    return 'Не удалось войти через Google. Попробуйте снова.';
  }
  if (lower.startsWith('yandex authentication failed')) {
    return 'Не удалось войти через Яндекс. Попробуйте снова.';
  }
  if (lower.startsWith('suggestions error')) {
    return 'Не удалось загрузить подсказки поиска';
  }
  if (lower.startsWith('user data validation failed')) {
    return 'Данные профиля не прошли проверку';
  }
  if (lower.startsWith('internal server error during login') ||
      lower.contains('internal server error during login')) {
    return 'Не удалось войти. Попробуйте позже.';
  }
  if (lower.startsWith('too many uploads')) {
    return 'Слишком много загрузок. Попробуйте позже.';
  }
  if (lower.contains('video init failed') || lower.contains('no video url')) {
    return 'Не удалось запустить видео';
  }
  if (lower.contains('err_name_not_resolved') ||
      lower.contains('err_internet_disconnected') ||
      lower.contains('err_address_unreachable')) {
    return 'Нет подключения. Проверьте интернет и попробуйте снова.';
  }
  if (lower.contains('err_connection') || lower.contains('err_timed_out')) {
    return 'Сервер не отвечает. Попробуйте ещё раз.';
  }
  if (lower.contains('too many requests') ||
      lower.contains('rate_limit') ||
      lower.contains('429')) {
    return 'Слишком много запросов. Подождите минуту и нажмите «Повторить».';
  }
  if (lower.contains('broken pipe') || lower.contains('socketwrite failed')) {
    return 'Соединение прервалось при загрузке. Проверьте интернет и попробуйте снова.';
  }
  if (lower.contains('connection reset') ||
      lower.contains('connection closed')) {
    return 'Соединение с сервером оборвалось. Попробуйте ещё раз.';
  }
  if (lower.contains('missingpluginexception') &&
      (lower.contains('webrtc') || lower.contains('flutterwebrtc'))) {
    return 'Не удалось запустить звонок в браузере. Обновите страницу и нажмите «Повторить».';
  }
  if (lower.contains('notallowederror') ||
      lower.contains('permission denied') ||
      lower.contains('notallowed')) {
    return 'Разрешите доступ к микрофону и камере, затем повторите звонок.';
  }
  if (lower.contains('notfounderror') ||
      lower.contains('requested device not found')) {
    return 'Микрофон или камера не найдены. Проверьте, что они не заняты.';
  }
  final statusMatch = RegExp(r'\((\d{3})\)\s*$').firstMatch(raw);
  if (statusMatch != null) {
    final code = int.tryParse(statusMatch.group(1)!);
    if (code != null) {
      final withoutCode =
          raw.replaceFirst(RegExp(r'\s*\(\d{3}\)\s*$'), '').trim();
      if (withoutCode.isNotEmpty &&
          !RegExp(r'^\S+\s+\(\d{3}\)$').hasMatch(raw)) {
        return withoutCode;
      }
      return _httpStatusMessage(code, fallback: fallback).message;
    }
  }
  return raw;
}

bool isAuthRelatedError(Object e) {
  if (e is ApiClientException && e.statusCode == 401) return true;
  final s = e.toString().toLowerCase();
  return s.contains('not authenticated') || s.contains('401');
}

/// Ошибка действия с учётом необходимости входа (лайк, репост и т.д.).
String userVisibleAuthError(
  Object e, {
  String fallback = 'Произошла ошибка',
  String authFallback = 'Войдите в аккаунт',
}) {
  if (isAuthRelatedError(e)) return authFallback;
  return userVisibleError(e, fallback: fallback);
}
