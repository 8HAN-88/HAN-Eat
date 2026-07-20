import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'web_app_update_service_stub.dart'
    if (dart.library.html) 'web_app_update_service_web.dart' as reload;

/// Авто-обновление web: сравнивает вшитый билд с [version.json] и
/// тихо перезагружает страницу при новом деплое (без кнопок для пользователя).
class WebAppUpdateService {
  WebAppUpdateService._();

  static const embeddedBuild = String.fromEnvironment(
    'WEB_BUILD_ID',
    defaultValue: '',
  );

  static Timer? _pollTimer;
  static Timer? _initialTimer;
  static bool _checking = false;
  static bool _reloadScheduled = false;
  static final ValueNotifier<String?> availableUpdateBuild =
      ValueNotifier<String?>(null);

  static void start() {
    if (!kIsWeb || embeddedBuild.isEmpty) return;
    _pollTimer?.cancel();
    _initialTimer?.cancel();

    // Даём приложению стабильно открыться, затем проверяем обновление.
    _initialTimer = Timer(const Duration(seconds: 12), () {
      unawaited(checkForUpdate(autoReload: true));
    });

    _pollTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(checkForUpdate(autoReload: true)),
    );
  }

  static void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialTimer?.cancel();
    _initialTimer = null;
  }

  /// [autoReload] — сразу применить новый билд без UI-баннера.
  static Future<void> checkForUpdate({bool autoReload = true}) async {
    if (!kIsWeb || embeddedBuild.isEmpty) return;
    if (_checking || _reloadScheduled) return;
    _checking = true;
    try {
      final uri = Uri.parse(
        '/version.json?nocache=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(
        uri,
        headers: const {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final remote = data['build_number']?.toString() ?? '';
      if (remote.isEmpty || remote == embeddedBuild) return;

      debugPrint(
        'WebAppUpdateService: новый билд $remote (текущий $embeddedBuild)',
      );
      availableUpdateBuild.value = remote;
      stop();
      if (autoReload) {
        await reloadNow();
      }
    } catch (e) {
      debugPrint('WebAppUpdateService: $e');
    } finally {
      _checking = false;
    }
  }

  static Future<void> reloadNow() async {
    if (!kIsWeb || _reloadScheduled) return;
    final build = availableUpdateBuild.value ?? embeddedBuild;
    _reloadScheduled = true;
    stop();
    await reload.reloadWebPage(build: build);
  }
}
