import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'app.dart';
import 'app_bootstrap_state.dart';
import 'bootstrap.dart';

/// Видимый экран загрузки → [HanEatApp] после минимального bootstrap.
class HanEatRoot extends StatefulWidget {
  const HanEatRoot({super.key});

  @override
  State<HanEatRoot> createState() => _HanEatRootState();
}

class _HanEatRootState extends State<HanEatRoot> {
  static const _bootOrange = Color(0xFFFF6B35);
  static const _bootCanvas = Color(0xFFF7F8FA);

  bool _uiReady = false;
  String _status = 'Запуск…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareUi());
    });
  }

  Future<void> _prepareUi() async {
    try {
      if (mounted) setState(() => _status = 'Инициализация…');
      await bootstrapEarly().timeout(
        const Duration(seconds: 6),
        onTimeout: () => debugPrint('⚠️ HanEatRoot bootstrapEarly timeout'),
      );
      if (mounted) setState(() => _status = 'Сессия…');
      await bootstrapServicesForFirstFrame().timeout(
        const Duration(seconds: 5),
        onTimeout: () => debugPrint('⚠️ HanEatRoot auth timeout'),
      );
    } catch (e, st) {
      debugPrint('HanEatRoot _prepareUi: $e\n$st');
    } finally {
      AppBootstrapState.authReady.value = true;
      AuthService.sessionRevision.value++;
      if (mounted) setState(() => _uiReady = true);
    }

    unawaited(() async {
      try {
        await bootstrapServicesDeferred();
      } catch (e, st) {
        debugPrint('HanEatRoot deferred: $e\n$st');
      } finally {
        AppBootstrapState.servicesReady.value = true;
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    if (_uiReady) return const HanEatApp();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bootOrange,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _bootCanvas,
      ),
      home: Scaffold(
        backgroundColor: _bootCanvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: _bootOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'HAN Eat',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: _bootOrange),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5C5C5C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
