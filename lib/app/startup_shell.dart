import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/cold_start_policy.dart';
import '../core/web/boot_ready_signal.dart';
import '../services/auth_service.dart';
import '../services/feed_api_cache.dart';
import '../services/story_feed_cache.dart';
import '../services/web_app_update_service.dart';
import '../utils/api_error_parser.dart';
import '../widgets/app_brand_logo.dart';
import 'startup_home_placeholder.dart';
import 'app.dart' deferred as full_app;
import 'app_bootstrap_state.dart';
import 'bootstrap.dart' deferred as heavy_boot;
import 'bootstrap_light.dart';
import 'web_auth_app.dart';
import 'web_plugins_heavy_stub.dart'
    if (dart.library.html) 'web_plugins_heavy.dart' deferred as heavy_plugins;

/// Фон загрузки — тёмный, без белой вспышки на PWA.
const _kStartupCanvas = Color(0xFF0F1319);

class StartupShell extends StatefulWidget {
  const StartupShell({super.key});

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell> {
  Object? _error;
  Object? _fullAppLoadError;
  bool _fullAppLibraryLoaded = false;
  bool _fullAppLoadStarted = false;
  bool _hasLocalSession = false;
  bool _htmlSplashSignaled = false;

  void _enterFullAppIfSessionReady() {
    if (!kIsWeb || AuthService.instance.currentUser != null) {
      AppBootstrapState.enterFullApp();
    }
  }

  void _openMainUi() {
    if (!AppBootstrapState.authReady.value) {
      AppBootstrapState.authReady.value = true;
      AuthService.sessionRevision.value++;
    }
    _enterFullAppIfSessionReady();
  }

  void _onSessionRevision() {
    if (!mounted) return;
    if (AuthService.instance.currentUser != null) {
      _openMainUi();
    }
  }

  @override
  void initState() {
    super.initState();
    AppBootstrapState.loadFullApp.addListener(_onLoadFullAppChanged);
    AuthService.sessionRevision.addListener(_onSessionRevision);
    // Качаем deferred-чанк сразу, параллельно с auth — иначе iPhone Safari
    // сидит 20–30 с на «Загружаем приложение…» после восстановления сессии.
    unawaited(_ensureFullAppLoaded());
    unawaited(_openFromDiskLikeInstagram());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runBootstrapInBackground());
    });
    Future<void>.delayed(Duration(seconds: kIsWeb ? 4 : 12), () {
      if (!mounted || AppBootstrapState.authReady.value) return;
      debugPrint('⚠️ StartupShell: timeout — открываем UI');
      _openMainUi();
    });
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (mounted && !AppBootstrapState.authReady.value) {
        debugPrint('⚠️ StartupShell: timeout 20s — открываем UI');
        _openMainUi();
      }
    });
  }

  @override
  void dispose() {
    AppBootstrapState.loadFullApp.removeListener(_onLoadFullAppChanged);
    AuthService.sessionRevision.removeListener(_onSessionRevision);
    super.dispose();
  }

  void _onLoadFullAppChanged() {
    if (AppBootstrapState.loadFullApp.value) {
      unawaited(_ensureFullAppLoaded());
    }
  }

  Future<void> _ensureFullAppLoaded() async {
    if (_fullAppLibraryLoaded || _fullAppLoadStarted) return;
    _fullAppLoadStarted = true;
    try {
      if (kIsWeb) {
        await full_app.loadLibrary().timeout(
              ColdStartPolicy.webFullAppLibraryTimeout,
            );
      } else {
        await full_app.loadLibrary();
      }
      if (!mounted) return;
      setState(() {
        _fullAppLibraryLoaded = true;
        _fullAppLoadError = null;
      });
      if (kIsWeb) {
        WebAppUpdateService.start();
      }
      unawaited(_loadHeavyAndBootstrap());
    } catch (e, st) {
      debugPrint('full_app.loadLibrary failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _fullAppLoadStarted = false;
        // Web: keep the disk shell and retry. An error screen here
        // is how people get stuck on 3G.
        if (!kIsWeb) _fullAppLoadError = e;
      });
      if (kIsWeb) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted && !_fullAppLibraryLoaded) {
            unawaited(_ensureFullAppLoaded());
          }
        });
      }
    }
  }

  Future<void> _loadHeavyAndBootstrap() async {
    try {
      final loaders = <Future<void>>[heavy_boot.loadLibrary()];
      if (kIsWeb) {
        loaders.add(heavy_plugins.loadLibrary());
      }
      await Future.wait<void>(loaders);
      if (kIsWeb) {
        heavy_plugins.registerHeavyWebPlugins();
      }
      if (!mounted) return;
      await _runHeavyBootstrap();
    } catch (e, st) {
      debugPrint('heavy load/bootstrap failed: $e\n$st');
      AppBootstrapState.servicesReady.value = true;
    }
  }

  Future<void> _runHeavyBootstrap() async {
    try {
      if (!kIsWeb) {
        await heavy_boot.bootstrapServicesForFirstFrame().timeout(
          const Duration(seconds: 6),
          onTimeout: () {
            debugPrint('⚠️ bootstrapServicesForFirstFrame: timeout');
          },
        );
      }
      await heavy_boot.bootstrapServicesDeferred();
    } catch (e, st) {
      debugPrint('heavy bootstrap: $e\n$st');
    } finally {
      AppBootstrapState.servicesReady.value = true;
    }
  }

  void _retryBootstrap() {
    setState(() {
      _error = null;
      _fullAppLoadError = null;
      _fullAppLibraryLoaded = false;
      _fullAppLoadStarted = false;
      AppBootstrapState.authReady.value = false;
      AppBootstrapState.hiveReady.value = false;
      AppBootstrapState.servicesReady.value = false;
      AppBootstrapState.primaryUiReady.value = false;
      AppBootstrapState.loadFullApp.value = false;
      _htmlSplashSignaled = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureFullAppLoaded());
      unawaited(_runBootstrapInBackground());
    });
  }

  Future<void> _openFromDiskLikeInstagram() async {
    unawaited(FeedApiCache.warmUp());
    unawaited(StoryFeedCache.warmUp());
    try {
      final restored = await AuthService.restoreLocalSession().timeout(
        const Duration(milliseconds: 600),
      );
      if (!mounted) return;
      if (restored) {
        setState(() => _hasLocalSession = true);
        _openMainUi();
      }
    } catch (e) {
      debugPrint('StartupShell local session: $e');
    }
  }

  Future<void> _runBootstrapInBackground() async {
    try {
      await bootstrapEarly().timeout(
        Duration(seconds: kIsWeb ? 2 : 8),
        onTimeout: () {
          debugPrint('⚠️ bootstrapEarly: timeout — продолжаем');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapEarly: $e\n$st');
    }

    try {
      await bootstrapAuthForFirstFrame().timeout(
        Duration(milliseconds: kIsWeb ? 2500 : 6000),
        onTimeout: () {
          debugPrint('⚠️ bootstrapAuthForFirstFrame: timeout');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapAuthForFirstFrame: $e\n$st');
      if (!kIsWeb && mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (AuthService.instance.currentUser != null && mounted) {
        setState(() => _hasLocalSession = true);
      }
      if (kIsWeb && AuthService.instance.currentUser == null) {
        try {
          final token = await AuthService.getAccessToken();
          if (token != null && token.isNotEmpty) {
            debugPrint('StartupShell: токен есть — открываем оболочку');
            if (mounted) setState(() => _hasLocalSession = true);
            _openMainUi();
            return;
          }
        } catch (_) {}
      }
      _openMainUi();
    }
  }

  void _signalHtmlSplashCanHide() {
    if (!kIsWeb || _htmlSplashSignaled) return;
    _htmlSplashSignaled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyPrimaryUiReady();
    });
  }

  /// На web HTML-сплэш уже крутится — второй логотип не рисуем.
  Widget _underHtmlSplash() {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _kStartupCanvas,
        body: SizedBox.expand(),
      ),
    );
  }

  Widget _loadingApp({String? subtitle}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _kStartupCanvas,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        backgroundColor: _kStartupCanvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppBrandLogo(
                    layout: AppBrandLogoLayout.horizontal,
                    width: 168,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(
                    color: Color(0xFFFF6B35),
                    strokeWidth: 2.5,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB0B8C4),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorApp() {
    final err = _error ?? _fullAppLoadError;
    final message = err != null
        ? userVisibleError(err, fallback: 'Не удалось подключиться к серверу')
        : 'Не удалось запустить приложение';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _kStartupCanvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 56),
                  const SizedBox(height: 20),
                  const Text(
                    'Не удалось запустить',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _retryBootstrap,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null || _fullAppLoadError != null) return _errorApp();

    return ValueListenableBuilder<bool>(
      valueListenable: AppBootstrapState.authReady,
      builder: (context, ready, _) {
        if (!ready) {
          if (_hasLocalSession) {
            // HTML splash stays until we signal ready. Show the disk shell
            // so 3G is not a blank brown page.
            if (kIsWeb) _signalHtmlSplashCanHide();
            return const StartupHomePlaceholder();
          }
          return kIsWeb ? _underHtmlSplash() : _loadingApp();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: AppBootstrapState.loadFullApp,
          builder: (context, wantFull, _) {
            if (kIsWeb && !wantFull && !_hasLocalSession) {
              _signalHtmlSplashCanHide();
              return const WebAuthApp();
            }
            if (!_fullAppLibraryLoaded) {
              unawaited(_ensureFullAppLoaded());
              if (_hasLocalSession || AuthService.instance.currentUser != null) {
                _signalHtmlSplashCanHide();
                return const StartupHomePlaceholder();
              }
              return kIsWeb
                  ? _underHtmlSplash()
                  : _loadingApp();
            }
            _signalHtmlSplashCanHide();
            return ProviderScope(child: full_app.HanEatApp());
          },
        );
      },
    );
  }
}
