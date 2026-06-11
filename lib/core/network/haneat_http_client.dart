import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_endpoint_resolver.dart';
import 'haneat_http_overrides.dart';

/// Общий HTTP-клиент для API (уважает [HanEatHttpOverrides] и таймауты соединения).
class HanEatHttpClient {
  HanEatHttpClient._();

  static http.Client? _instance;

  static const _allowedHosts = HanEatHttpOverrides.allowedHosts;

  static http.Client get shared {
    final existing = _instance;
    if (existing != null) return existing;

    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..idleTimeout = const Duration(seconds: 90);

    if (!kReleaseMode || ApiEndpointResolver.usingIpFallback) {
      ioClient.badCertificateCallback = (cert, host, port) {
        if (_allowedHosts.contains(host) ||
            ApiEndpointResolver.hostNeedsSslRelaxation(host)) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ SSL bypass $host:$port (issuer=${cert.issuer})',
            );
          }
          return true;
        }
        return false;
      };
    }

    _instance = IOClient(ioClient);
    return _instance!;
  }

  @visibleForTesting
  static void resetForTest() => _instance = null;
}
