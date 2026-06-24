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

  @visibleForTesting
  static void resetForTest() {
    recreateShared();
  }
}
