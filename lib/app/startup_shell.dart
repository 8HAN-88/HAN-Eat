import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../utils/api_error_parser.dart';
import '../widgets/app_brand_logo.dart';
import 'app.dart';
import 'app_bootstrap_state.dart';
import 'bootstrap.dart';

/// Фон загрузки — тёмный, без белой вспышки на PWA.
const _kStartupCanvas = Color(0xFF0F1319);

class StartupShell extends StatefulWidget {
  const StartupShell({super.key});

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell> {
  Object? _error;

  void _openMainUi() {
    if (AppBootstrapState.authReady.value) return;
    AppBootstrapState.authReady.value = true;
    AuthService.sessionRevision.value++;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runBootstrapInBackground());
    });
    // Страховка: если bootstrap завис — не вечный спиннер (сессия уже могла восстановиться).
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (mounted && !AppBootstrapState.authReady.value) {
        debugPrint('⚠️ StartupShell: timeout 12s — открываем UI');
        _openMainUi();
      }
    });
  }

  void _retryBootstrap() {
    setState(() {
      _error = null;
      AppBootstrapState.authReady.value = false;
      AppBootstrapState.hiveReady.value = false;
      AppBootstrapState.servicesReady.value = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runBootstrapInBackground());
    });
  }

  Future<void> _runBootstrapInBackground() async {
    try {
      await bootstrapEarly().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('⚠️ bootstrapEarly: timeout 8s — продолжаем');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapEarly: $e\n$st');
    }

    try {
      await bootstrapServicesForFirstFrame().timeout(
        Duration(milliseconds: kIsWeb ? 500 : 6000),
        onTimeout: () {
          debugPrint('⚠️ bootstrapServicesForFirstFrame: timeout');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapServicesForFirstFrame: $e\n$st');
      if (mounted) setState(() => _error = e);
    } finally {
      // Только после восстановления сессии — иначе redirect на /login при F5.
      _openMainUi();
    }

    unawaited(() async {
      try {
        await bootstrapServicesDeferred();
      } catch (e, st) {
        debugPrint('bootstrapServicesDeferred: $e\n$st');
      } finally {
        AppBootstrapState.servicesReady.value = true;
      }
    }());
  }

  Widget _loadingApp() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _kStartupCanvas,
        brightness: Brightness.dark,
      ),
      home: const Scaffold(
        backgroundColor: _kStartupCanvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppBrandLogo(
                    layout: AppBrandLogoLayout.horizontal,
                    width: 168,
                  ),
                  SizedBox(height: 32),
                  CircularProgressIndicator(
                    color: Color(0xFFFF6B35),
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorApp() {
    final message = _error != null
        ? userVisibleError(_error!, fallback: 'Не удалось подключиться к серверу')
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
    if (_error != null) return _errorApp();

    return ValueListenableBuilder<bool>(
      valueListenable: AppBootstrapState.authReady,
      builder: (context, ready, _) {
        if (!ready) return _loadingApp();
        return const HanEatApp();
      },
    );
  }
}

/// Для integration-тестов: тот же вход, что и [main].
void runHanEatApp() {
  AppBootstrapState.authReady.value = false;
  runApp(
    const ProviderScope(
      child: HanEatApp(),
    ),
  );
}
