import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_endpoint_resolver.dart';

/// iOS Simulator иногда не принимает новую цепочку Let's Encrypt (E8/ECDSA),
/// хотя сертификат валиден. В debug поднимаем доверие только для api.haneat.app.
class HanEatHttpOverrides extends HttpOverrides {
  static const allowedHosts = {
    'api.haneat.app',
    'haneat.app',
    'www.haneat.app',
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 25)
      ..idleTimeout = const Duration(seconds: 90);
    // debug/profile: Let's Encrypt; release+IP fallback: сертификат на api.haneat.app, не на IP.
    if (!kReleaseMode || ApiEndpointResolver.usingIpFallback) {
      client.badCertificateCallback = (cert, host, port) {
        if (allowedHosts.contains(host) ||
            ApiEndpointResolver.hostNeedsSslRelaxation(host)) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ SSL bypass for $host:$port (issuer=${cert.issuer})',
            );
          }
          return true;
        }
        return false;
      };
    }
    return client;
  }
}
