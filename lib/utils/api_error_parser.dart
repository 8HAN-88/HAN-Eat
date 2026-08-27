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
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}

String parseApiErrorMessage(
  dynamic detail, {
  String fallback = 'Произошла ошибка',
}) {
  if (detail == null) return fallback;
  if (detail is String) {
    return switch (detail) {
      'network_error' =>
        'Нет подключения к серверу. Проверьте интернет и попробуйте снова.',
      'timeout' => 'Превышено время ожидания ответа от сервера',
      'offline' => 'Войдите в аккаунт',
      'group_slow_mode' =>
        'Слишком часто. В этом чате включен slow mode, подождите немного.',
      'group_flood_limited' =>
        'Превышен лимит сообщений в минуту. Подождите и попробуйте снова.',
      'paid_media_locked' =>
        'Сначала откройте платное медиа, чтобы переслать',
      'pack_not_installed' =>
        'Сначала установите пак, чтобы закрепить его',
      'not_for_sale' => 'Пак сейчас не продаётся',
      _ => detail,
    };
  }
  if (detail is Map) {
    final msg = detail['message'] as String?;
    if (msg != null && msg.isNotEmpty) return msg;
    final code = detail['code'] as String?;
    if (code == 'STARS_REQUIRED') {
      return 'Недостаточно звёзд';
    }
    if (code == 'pack_purchase_required') {
      return 'Сначала купите пак';
    }
    if (code == 'custom_emoji_denied') {
      return 'Этот эмодзи недоступен — купите пак';
    }
    if (code == 'price_changed') {
      return 'Цена пака изменилась. Обновите витрину и подтвердите снова';
    }
    if (code == 'not_for_sale') {
      return 'Пак сейчас не продаётся';
    }
    if (code == 'own_pack') {
      return 'Нельзя купить свой пак';
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

/// Текст ошибки для SnackBar / диалогов.
String userVisibleError(Object e, {String fallback = 'Произошла ошибка'}) {
  if (e is ApiClientException) return e.message;
  if (e is TimeoutException) {
    return 'Превышено время ожидания ответа от сервера';
  }
  if (_isNetworkError(e)) {
    return 'Нет подключения к серверу. Проверьте интернет и попробуйте снова.';
  }
  final raw = e.toString().replaceAll('Exception: ', '').trim();
  if (raw.isEmpty) return fallback;
  if (raw == 'Not authenticated') return 'Войдите в аккаунт';
  final lower = raw.toLowerCase();
  if (lower.contains('voice_privacy_denied')) {
    return 'Собеседник не принимает голосовые и кружки';
  }
  if (lower.contains('call_privacy_denied')) {
    return 'Собеседник не принимает звонки';
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
