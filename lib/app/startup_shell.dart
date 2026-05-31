import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'bootstrap.dart';
import '../core/theme/app_theme.dart';

/// Показывает UI сразу после [bootstrapEarly], тяжёлую часть ([bootstrapServices])
/// выполняет после первого кадра — иначе на macOS с merged UI thread окно
/// долго остаётся «пустым», пока блокируется поток Firebase/плагинов.
class StartupShell extends StatefulWidget {
  const StartupShell({super.key});

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runHeavyInit());
  }

  Future<void> _runHeavyInit() async {
    try {
      await bootstrapServices();
    } catch (e, st) {
      debugPrint('bootstrapServices: $e\n$st');
      if (mounted) {
        setState(() => _error = e);
      }
      return;
    }
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SelectableText(
                  'Ошибка инициализации сервисов:\n\n$_error',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  'HAN Eat',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Запуск…',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const HanEatApp();
  }
}

/// Корень приложения: один [ProviderScope] на весь цикл (splash → HanEatApp).
void runHanEatApp() {
  runApp(
    const ProviderScope(
      child: StartupShell(),
    ),
  );
}
