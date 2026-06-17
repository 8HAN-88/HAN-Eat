import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'web_app_update_service_stub.dart'
    if (dart.library.html) 'web_app_update_service_web.dart' as reload;

/// Авто-обновление PWA/web: сравнивает вшитый билд с [version.json] на сервере.
class WebAppUpdateService {
  WebAppUpdateService._();

  static const embeddedBuild = String.fromEnvironment(
    'WEB_BUILD_ID',
    defaultValue: '',
  );

  static Timer? _pollTimer;
  static bool _checking = false;
  static bool _reloadScheduled = false;

  static void start() {
    if (!kIsWeb || embeddedBuild.isEmpty) return;
    _pollTimer?.cancel();
    unawaited(checkForUpdate());
    _pollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(checkForUpdate()),
    );
  }

  static void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static Future<void> checkForUpdate() async {
    if (!kIsWeb || embeddedBuild.isEmpty) return;
    if (_checking || _reloadScheduled) return;
    _checking = true;
    try {
      final uri = Uri.parse(
        '/version.json?nocache=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(
            uri,
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final remote = data['build_number']?.toString() ?? '';
      if (remote.isEmpty || remote == embeddedBuild) return;

      debugPrint(
        'WebAppUpdateService: новый билд $remote (текущий $embeddedBuild) — перезагрузка',
      );
      _reloadScheduled = true;
      stop();
      await reload.reloadWebPage(build: remote);
    } catch (e) {
      debugPrint('WebAppUpdateService: $e');
    } finally {
      _checking = false;
    }
  }
}
