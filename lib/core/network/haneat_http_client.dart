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

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
    platform.resetHanEatHttpClientForTest();
  }
}
