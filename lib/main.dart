import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app/bootstrap.dart';
import 'core/network/haneat_http_overrides.dart';
import 'app/startup_shell.dart';
import 'core/crash_reporting.dart';

Future<void> main() async {
  // Настройка глобального обработчика ошибок Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ Flutter Error: ${details.exception}');
    if (details.stack != null) {
      debugPrint('Stack trace: ${details.stack}');
    }
  };

  // run inside zone to catch uncaught async errors
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb) {
      HttpOverrides.global = HanEatHttpOverrides();
    }

    // В release при падении build часто «пустой» экран — показываем текст ошибки.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: Colors.white,
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

    try {
      await bootstrapEarly();
      runHanEatApp();
    } catch (e, st) {
      debugPrint('❌ bootstrapEarly failed: $e\n$st');
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SelectableText(
                    'Не удалось запустить приложение.\n\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }, (error, stack) {
    debugPrint('❌ Uncaught zone error: $error');
    debugPrint('Stack trace: $stack');
    unawaited(CrashReporting.recordError(error, stack, fatal: true));
  });
}
