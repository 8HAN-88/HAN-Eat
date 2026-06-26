import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_router.dart';
import 'theme_mode_controller.dart';
import '../core/theme/app_theme.dart';
import '../services/api_reachability_service.dart';
import '../services/account_session_service.dart';
import '../services/auth_service.dart';
import '../services/user_realtime_service.dart';
import '../services/web_app_update_service.dart';
import '../features/settings/application/subscription_status_provider.dart';

class HanEatApp extends ConsumerStatefulWidget {
  const HanEatApp({super.key});

  @override
  ConsumerState<HanEatApp> createState() => _HanEatAppState();
}

class _HanEatAppState extends ConsumerState<HanEatApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _deepLinkSubscription;
  late final void Function(User?) _onAccountSessionChanged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onAccountSessionChanged = (_) {
      if (!mounted) return;
      ref.read(subscriptionStatusRefreshProvider.notifier).state++;
    };
    AccountSessionService.registerListener(_onAccountSessionChanged);
    if (!kIsWeb) {
      _deepLinkSubscription = AppLinks().uriLinkStream.listen(
        (uri) {
          final path = parseDeepLinkToGoPath(uri.toString());
          if (path != null) {
            ref.read(appRouterProvider).go(path);
          }
        },
        onError: (Object e) => debugPrint('uriLinkStream: $e'),
      );
    }
    if (kIsWeb) {
      WebAppUpdateService.start();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WebAppUpdateService.stop();
    }
    AccountSessionService.unregisterListener(_onAccountSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) {
      // На web lifecycle ненадёжен (маршруты, клавиатура) — realtime только через visibility API.
      if (state == AppLifecycleState.resumed) {
        UserRealtimeService.instance.resumeFromBackground();
        unawaited(ApiReachabilityService.instance.warmUp(force: true));
        unawaited(AuthService.getAccessTokenForApi());
        unawaited(WebAppUpdateService.checkForUpdate());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      UserRealtimeService.instance.resumeFromBackground();
      unawaited(ApiReachabilityService.instance.checkNow());
      unawaited(AuthService.getAccessTokenForApi());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      UserRealtimeService.instance.pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final router = ref.watch(appRouterProvider);
      final themeMode = ref.watch(themeModeProvider);

      return MaterialApp.router(
        title: 'HAN Eat',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ru', 'RU'),
          Locale('en', 'US'),
        ],
        locale: const Locale('ru', 'RU'),
        builder: (context, child) {
          final theme = Theme.of(context);
          final canvas = theme.scaffoldBackgroundColor;
          final defaultBody = theme.textTheme.bodyMedium ?? const TextStyle();
          final media = MediaQuery.of(context);
          final content = child ??
              Scaffold(
                backgroundColor: canvas,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.restaurant_rounded,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      CircularProgressIndicator(
                          color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Загрузка HAN Eat…',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.35,
              ),
            ),
            child: ColoredBox(
              color: canvas,
              child: DefaultTextStyle(
                style: defaultBody.copyWith(color: theme.colorScheme.onSurface),
                child: Stack(
                  children: [
                    content,
                    if (kIsWeb)
                      ValueListenableBuilder<String?>(
                        valueListenable:
                            WebAppUpdateService.availableUpdateBuild,
                        builder: (context, build, _) {
                          if (build == null || build.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            left: 12,
                            right: 12,
                            top: media.padding.top + 8,
                            child: _WebUpdateBanner(buildNumber: build),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      // Если есть ошибка при построении, показываем экран ошибки
      debugPrint('❌ Ошибка при построении HanEatApp: $e');
      debugPrint('Stack trace: $stackTrace');
      return MaterialApp(
        title: 'HAN Eat',
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Не удалось запустить приложение. '
                  'Перезапустите или переустановите HAN Eat.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('Закрыть приложение'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}

class _WebUpdateBanner extends StatelessWidget {
  const _WebUpdateBanner({required this.buildNumber});

  final String buildNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded,
                color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Доступна новая версия HAN Eat',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Build $buildNumber',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: WebAppUpdateService.reloadNow,
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}
