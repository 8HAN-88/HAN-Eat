import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Crashlytics (release). Ошибки логируются, но не роняют процесс.
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

      _ready = true;
      if (kDebugMode) {
        debugPrint('Crashlytics: готов (сбор в release, без fatal)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Crashlytics init skipped: $e');
    }
  }

  static Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.recordFlutterError(details);
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
        fatal: false,
      );
    } catch (_) {}
  }
}
