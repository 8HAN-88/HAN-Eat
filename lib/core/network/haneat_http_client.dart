import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  /// Выполнить запрос через shared-клиент; при close — пересоздать и повторить.
  static Future<T> withShared<T>(
    Future<T> Function(http.Client client) action,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await action(shared);
      } on http.ClientException {
        if (attempt == 0) {
          recreateShared();
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
    try {
      _instance?.close();
    } catch (_) {}
    _instance = null;
    platform.resetHanEatHttpClientForTest();
  }

  /// Вызвать при старте / возврате из фона — сброс «закрытого» singleton.
  static void ensureHealthy() => recreateShared();

  @visibleForTesting
  static void resetForTest() {
    recreateShared();
  }
}
