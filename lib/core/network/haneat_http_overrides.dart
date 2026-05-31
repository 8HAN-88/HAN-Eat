import 'dart:io';

import 'package:flutter/foundation.dart';

/// iOS Simulator иногда не принимает новую цепочку Let's Encrypt (E8/ECDSA),
/// хотя сертификат валиден. В debug поднимаем доверие только для api.haneat.app.
class HanEatHttpOverrides extends HttpOverrides {
  static const _allowedHosts = {'api.haneat.app', 'haneat.app', 'www.haneat.app'};

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (kDebugMode) {
      client.badCertificateCallback = (cert, host, port) {
        if (_allowedHosts.contains(host)) {
          debugPrint(
            '⚠️ SSL debug bypass for $host:$port (issuer=${cert.issuer})',
          );
          return true;
        }
        return false;
      };
    }
    return client;
  }
}
