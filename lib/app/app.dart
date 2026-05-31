import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_router.dart';
import 'theme_mode_controller.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/account_session_service.dart';
import '../services/auth_service.dart';
import '../features/settings/application/subscription_status_provider.dart';

class HanEatApp extends ConsumerStatefulWidget {
  const HanEatApp({super.key});

  @override
  ConsumerState<HanEatApp> createState() => _HanEatAppState();
}

class _HanEatAppState extends ConsumerState<HanEatApp> with WidgetsBindingObserver {
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
  }

  @override
  void dispose() {
    AccountSessionService.unregisterListener(_onAccountSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ApiService.touchAiScanCreditsSilently());
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
          final defaultBody = theme.textTheme.bodyMedium ?? const TextStyle();
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
            child: DefaultTextStyle(
              style: defaultBody,
              child: child ??
                  Scaffold(
                    backgroundColor: theme.scaffoldBackgroundColor,
                    body: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Загрузка приложения...'),
                        ],
                      ),
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
