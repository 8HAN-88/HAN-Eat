import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Crashlytics (release). В debug только лог в консоль.
class CrashReporting {
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> initialize({required bool firebaseInitialized}) async {
    if (_ready || !firebaseInitialized) return;
    try {
      if (Firebase.apps.isEmpty) return;

      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        kReleaseMode,
      );

      final defaultOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        defaultOnError?.call(details);
        unawaited(recordFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(recordError(error, stack, fatal: true));
        return true;
      };

      _ready = true;
      if (kDebugMode) {
        debugPrint('Crashlytics: готов (сбор в release)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Crashlytics init skipped: $e');
    }
  }

  static Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (_) {}
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('CrashReporting: $error');
      if (stack != null) debugPrint('$stack');
      return;
    }
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
      );
    } catch (_) {}
  }
}
