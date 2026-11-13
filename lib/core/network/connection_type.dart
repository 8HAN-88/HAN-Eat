import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Подписка на сеть. На Linux без NetworkManager плагин бросает ошибку
/// из async onListen — ловим её здесь, чтобы старт приложения не падал.
void watchConnectivity(void Function(List<ConnectivityResult> result) onData) {
  runZonedGuarded(() {
    Connectivity().onConnectivityChanged.listen(
      onData,
      onError: (Object error, StackTrace stack) {
        if (kDebugMode) debugPrint('connectivity: $error');
      },
    );
  }, (Object error, StackTrace stack) {
    if (kDebugMode) debugPrint('connectivity: $error');
  });
}

/// Текущее состояние сети. null, если NetworkManager недоступен.
Future<List<ConnectivityResult>?> readConnectivity() {
  final done = Completer<List<ConnectivityResult>?>();
  runZonedGuarded(() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (!done.isCompleted) done.complete(result);
    } catch (error) {
      if (kDebugMode) debugPrint('connectivity: $error');
      if (!done.isCompleted) done.complete(null);
    }
  }, (Object error, StackTrace stack) {
    if (kDebugMode) debugPrint('connectivity: $error');
    if (!done.isCompleted) done.complete(null);
  });
  return done.future;
}

/// Wi‑Fi или Ethernet (не сотовая сеть).
Future<bool> deviceOnWifiOrEthernet() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  } catch (_) {
    return true;
  }
}
