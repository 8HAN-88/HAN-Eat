import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app/bootstrap.dart';

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
    await bootstrap();
  }, (error, stack) {
    // Replace with proper error reporting later.
    // For now print to console so dev can see errors.
    debugPrint('❌ Uncaught zone error: $error');
    debugPrint('Stack trace: $stack');
  });
}
