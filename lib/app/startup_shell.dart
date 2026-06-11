import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../utils/api_error_parser.dart';
import '../widgets/app_brand_logo.dart';
import 'app.dart';
import 'app_bootstrap_state.dart';
import 'bootstrap.dart';

/// Фон загрузки — не чисто белый, чтобы отличать от зависшего Launch Screen.
const _kStartupCanvas = Color(0xFFF2F4F7);

class StartupShell extends StatefulWidget {
  const StartupShell({super.key});

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell> {
  Object? _error;
  String _status = 'Запуск…';

  void _openMainUi() {
    if (AppBootstrapState.authReady.value) return;
    AppBootstrapState.authReady.value = true;
    AuthService.sessionRevision.value++;
  }

  @override
  void initState() {
    super.initState();
    // Первый кадр — сразу основной UI; bootstrap не блокирует экран.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openMainUi();
      unawaited(_runBootstrapInBackground());
    });
    // Страховка: если postFrame не сработал — через 2 с всё равно открываем UI.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) _openMainUi();
    });
  }

  void _retryBootstrap() {
    setState(() {
      _error = null;
      _status = 'Запуск…';
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
      if (mounted) setState(() => _status = 'Подключение к серверу…');
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
      if (mounted) setState(() => _status = 'Восстановление сессии…');
      await bootstrapServicesForFirstFrame().timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          debugPrint('⚠️ bootstrapServicesForFirstFrame: timeout 6s');
        },
      );
    } catch (e, st) {
      debugPrint('bootstrapServicesForFirstFrame: $e\n$st');
      if (mounted) setState(() => _error = e);
    } finally {
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
    // Минимальный UI без ассетов/темы — быстрее первый кадр на физическом iPhone.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _kStartupCanvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B35),
          brightness: Brightness.light,
        ),
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
                  const AppBrandLogo(size: 72),
                  const SizedBox(height: 20),
                  Icon(
                    Icons.restaurant_rounded,
                    size: 40,
                    color: Color(0xFFFF6B35),
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(
                    color: Color(0xFFFF6B35),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'HAN Eat',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
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
