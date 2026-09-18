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
      'Сортировка: relevance, date или popularity',
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
        'Слишком часто. В этом чате включен slow mode, подождите немного.',
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
    if (msg != null && msg.isNotEmpty) return msg;
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
      return 'Слишком часто. В этом чате включен slow mode, подождите немного.';
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
    return 'Не удалось выполнить действие. Попробуйте ещё раз.';
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
