import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_router.dart';
import 'theme_mode_controller.dart';
import '../core/theme/app_theme.dart';

class HanEatApp extends ConsumerWidget {
  const HanEatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Обработка ошибок при построении UI
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child ?? Scaffold(
              backgroundColor: Colors.white,
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
                Text('Ошибка инициализации: $e'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Попытка перезапуска
                  },
                  child: const Text('Перезагрузить'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
