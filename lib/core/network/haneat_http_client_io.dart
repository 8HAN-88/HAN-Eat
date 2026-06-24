import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'api_endpoint_resolver.dart';
import 'haneat_http_overrides.dart';

http.Client? _ioInstance;

http.Client createHanEatHttpClient() {
  final existing = _ioInstance;
  if (existing != null) return existing;

  _ioInstance = _buildIoClient();
  return _ioInstance!;
}

/// Отдельный клиент для долгих SSE-потоков (не закрывать [createHanEatHttpClient]).
http.Client createHanEatStreamClient() => _buildIoClient();

IOClient _buildIoClient() {
  final ioClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 25)
    ..idleTimeout = const Duration(seconds: 90);

  if (!kReleaseMode || ApiEndpointResolver.usingIpFallback) {
    ioClient.badCertificateCallback = (cert, host, port) {
      if (HanEatHttpOverrides.allowedHosts.contains(host) ||
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

  return IOClient(ioClient);
}

void resetHanEatHttpClientForTest() => _ioInstance = null;

http.Client createHanEatUploadClient() => _buildIoClient();
