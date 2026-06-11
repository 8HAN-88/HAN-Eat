import 'dart:async';

import 'package:flutter/material.dart';

import 'crash_reporting.dart';

/// Глобальные перехватчики: ошибки UI не роняют процесс в release.
class AppStabilityGuard {
  AppStabilityGuard._();

  static void install() {
    final priorFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      priorFlutterOnError?.call(details);
      debugPrint('❌ Flutter Error: ${details.exception}');
      if (details.stack != null) {
        debugPrint('${details.stack}');
      }
      if (CrashReporting.isReady) {
        unawaited(CrashReporting.recordFlutterError(details));
      }
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: const Color(0xFFFFF5F5),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'Ошибка интерфейса:\n${details.exceptionAsString()}',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ),
      );
    };
  }

  static void handleZoneError(Object error, StackTrace stack) {
    debugPrint('❌ Uncaught zone error: $error');
    debugPrint('Stack trace: $stack');
    if (CrashReporting.isReady) {
      unawaited(CrashReporting.recordError(error, stack, fatal: false));
    }
  }
}
