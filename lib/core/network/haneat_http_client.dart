import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_endpoint_resolver.dart';
import 'haneat_http_client_io.dart'
    if (dart.library.html) 'haneat_http_client_web.dart' as platform;

/// Общий HTTP-клиент для API.
/// На web — браузерный [http.Client]; на mobile/desktop — [IOClient].
class HanEatHttpClient {
  HanEatHttpClient._();

  static http.Client? _instance;

  static http.Client get shared {
    return _instance ??= platform.createHanEatHttpClient();
  }

  static bool _isRetryableNetworkError(Object error) {
    if (error is http.ClientException || error is TimeoutException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection timed out') ||
        text.contains('connection reset') ||
        text.contains('broken pipe') ||
        text.contains('network is unreachable') ||
        text.contains('handshakeexception') ||
        text.contains('tlsv1_alert');
  }

  /// Выполнить запрос через shared-клиент; при close — пересоздать и повторить.
  static Future<T> withShared<T>(
    Future<T> Function(http.Client client) action,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await action(shared);
      } catch (error) {
        final canRetry = attempt < 3 && _isRetryableNetworkError(error);
        if (canRetry) {
          await ApiEndpointResolver.revalidateIfNeeded();
          recreateShared();
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    throw StateError('HanEatHttpClient.withShared unreachable');
  }

  /// Долгоживущие SSE — отдельный клиент, его можно закрывать без влияния на API.
  static http.Client createStreamClient() =>
      platform.createHanEatStreamClient();

  /// Одноразовый клиент для загрузки файлов (S3 PUT / mock API).
  static http.Client createUploadClient() =>
      platform.createHanEatUploadClient();

  /// Пересоздать shared после случайного close (защита от регрессий).
  static void recreateShared() {
    if (kIsWeb) {
      _instance = null;
      platform.resetHanEatHttpClientForTest();
      return;
    }
    try {
      _instance?.close();
    } catch (_) {}
    _instance = null;
    platform.resetHanEatHttpClientForTest();
  }

  /// Вызвать при старте / возврате из фона — только на mobile/desktop.
  static void ensureHealthy() {
    if (!kIsWeb) recreateShared();
  }

  @visibleForTesting
  static void resetForTest() {
    recreateShared();
  }
}
