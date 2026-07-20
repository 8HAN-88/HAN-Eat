import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_build_config.dart';
import '../core/config/google_auth_config.dart';
import '../core/config/legacy_firestore_config.dart';
import '../core/network/api_endpoint_resolver.dart';
import '../services/auth_service.dart';
import '../services/server_config.dart';

/// Начальная глубокая ссылка (haneat://...) при запуске приложения.
String? initialDeepLink;

/// Лёгкая часть до первого кадра UI. Без Firebase / push / Hive / caches —
/// чтобы web cold-start не тащил полный [app_router] в первый JS-чанк.
Future<void> bootstrapEarly() async {
  if (!kIsWeb) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('dotenv load error (continuing): $e');
    }
  }
  // Web must resolve too: otherwise we stay on api.haneat.app and can brick
  // the PWA when CORS/env drifts (blank/white boot).
  await ApiEndpointResolver.resolve().timeout(
    Duration(seconds: kIsWeb ? 5 : 3),
    onTimeout: () {
      debugPrint(
        '⚠️ ApiEndpointResolver: timeout — продолжаем с конфигом по умолчанию',
      );
    },
  );

  debugPrint(
    '📡 HANEAT env=${AppBuildConfig.environment} API ${ServerConfig.apiBaseUrl}'
    '${ApiEndpointResolver.usingIpFallback ? ' (IP fallback)' : ''}',
  );
  if (kReleaseMode && !AppBuildConfig.apiBaseWasConfigured) {
    debugPrint(
      '⚠️ Release без --dart-define=HANEAT_API_BASE — используется ${AppBuildConfig.apiBaseRoot}',
    );
  }
  if (LegacyFirestoreConfig.disabled) {
    debugPrint('Legacy Firestore sync: отключён (release)');
  }
  final linkTimeout = (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android))
      ? const Duration(milliseconds: 600)
      : const Duration(seconds: 2);

  unawaited(() async {
    try {
      final uri = await AppLinks()
          .getInitialLink()
          .timeout(linkTimeout, onTimeout: () => null);
      if (uri != null) initialDeepLink = uri.toString();
    } catch (e) {
      debugPrint('getInitialLink error: $e');
    }
  }());
  unawaited(() async {
    try {
      await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('SharedPreferences at bootstrap: $e');
    }
  }());

  if (!kIsWeb) {
    try {
      if (GoogleAuthConfig.isConfigured) {
        debugPrint('Google Sign-In: Web client ID загружен');
        final scheme = GoogleAuthConfig.iosReversedClientId;
        if (scheme != null) {
          debugPrint(
            'Google Sign-In iOS: добавьте в Info.plist CFBundleURLSchemes → $scheme',
          );
        }
      }
    } catch (e) {
      debugPrint('dotenv load error (continuing): $e');
    }
  } else {
    debugPrint('Skipping .env load on web platform');
  }
}

/// Только восстановление сессии — достаточно для login/register UI.
Future<void> bootstrapAuthForFirstFrame() async {
  try {
    await AuthService.init(deferTokenRefresh: true);
  } catch (e) {
    debugPrint('AuthService init error (сессия из кэша сохранена): $e');
  }
}
