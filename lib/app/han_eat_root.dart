import 'dart:async';

import 'package:flutter/foundation.dart';
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
  static const _bootCanvas = Color(0xFF0F1319);

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
        Duration(seconds: kIsWeb ? 4 : 6),
        onTimeout: () => debugPrint('⚠️ HanEatRoot bootstrapEarly timeout'),
      );
      if (mounted) setState(() => _status = 'Сессия…');
      await bootstrapServicesForFirstFrame().timeout(
        Duration(seconds: kIsWeb ? 2 : 5),
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
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bootOrange,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _bootCanvas,
      ),
      home: Scaffold(
        backgroundColor: _bootCanvas,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/brand_logo.png',
                  width: 160,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                const SizedBox(height: 28),
                const CircularProgressIndicator(color: _bootOrange),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
