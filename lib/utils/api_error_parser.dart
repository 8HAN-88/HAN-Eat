/// Разбор ошибок FastAPI (`detail` как строка, объект или список).
class ApiClientException implements Exception {
  const ApiClientException({
    required this.message,
    this.statusCode,
    this.code,
  });

  final int? statusCode;
  final String? code;
  final String message;

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
  if (detail is String) return detail;
  if (detail is Map) {
    final msg = detail['message'] as String?;
    if (msg != null && msg.isNotEmpty) return msg;
    final code = detail['code'] as String?;
    if (code == 'CONTENT_BLOCKED') {
      return 'Публикация не прошла модерацию и не может быть опубликована';
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

ApiClientException apiExceptionFromResponse(
  int statusCode,
  Map<String, dynamic> body, {
  String fallback = 'Произошла ошибка',
}) {
  final detail = body['detail'];
  return ApiClientException(
    statusCode: statusCode,
    code: parseApiErrorCode(detail),
    message: parseApiErrorMessage(detail, fallback: fallback),
  );
}

/// Текст ошибки для SnackBar / диалогов.
String userVisibleError(Object e, {String fallback = 'Произошла ошибка'}) {
  if (e is ApiClientException) return e.message;
  final raw = e.toString().replaceAll('Exception: ', '').trim();
  if (raw.isEmpty) return fallback;
  if (raw == 'Not authenticated') return 'Войдите в аккаунт';
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
