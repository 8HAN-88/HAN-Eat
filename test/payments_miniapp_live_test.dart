import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/auth/presentation/login_screen.dart';
import 'package:han_eat/features/auth/presentation/register_screen.dart';
import 'package:han_eat/features/community/presentation/community_upload_screen.dart';
import 'package:han_eat/features/miniapps/presentation/miniapp_webview_screen.dart';
import 'package:han_eat/features/settings/presentation/stars_checkout_result_screen.dart';
import 'package:han_eat/features/settings/presentation/subscription_screen.dart';
import 'package:han_eat/features/settings/presentation/subscription_success_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:9';
    client.connectionTimeout = const Duration(milliseconds: 200);
    return client;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _OfflineHttp();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpRoute(
    WidgetTester tester, {
    required String location,
    required Widget child,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: location, builder: (_, __) => child),
        GoRoute(
          path: '/:rest(.*)',
          builder: (_, state) => Scaffold(
            appBar: AppBar(title: Text('opened:${state.uri}')),
            body: Text('opened:${state.uri}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> expectLanded(WidgetTester tester, String path) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('opened:$path'), findsWidgets);
  }

  Future<void> pumpSeconds(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 2; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('mini-app link that fails to open can retry', (tester) async {
    await pumpRoute(
      tester,
      location: '/webapp/3',
      child: const MiniAppOpenLoaderScreen(miniAppId: 3),
    );
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось открыть'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось открыть'), findsOneWidget);
    await tester.tap(find.text('В каталог'));
    await expectLanded(tester, '/mini-apps');
  });

  testWidgets('subscription return says the status could not be checked', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/subscription/success',
      child: const SubscriptionSuccessScreen(),
    );
    expect(find.text('Проверка статуса подписки…'), findsOneWidget);
    await pumpSeconds(tester, 25);
    expect(find.text('Не удалось проверить оплату'), findsOneWidget);
    expect(find.text('Обработка платежа'), findsNothing);
    await tester.tap(find.text('Проверить снова'));
    await tester.pump();
    expect(find.text('Проверка статуса подписки…'), findsOneWidget);
    await pumpSeconds(tester, 25);
    expect(find.text('Не удалось проверить оплату'), findsOneWidget);
    await tester.tap(find.text('Вернуться к подписке'));
    await expectLanded(tester, '/subscription/flex');
  });

  testWidgets('stars purchase return can retry and open the wallet', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/paid/success',
      child: const StarsCheckoutSuccessScreen(),
    );
    await pumpSeconds(tester, 20);
    expect(find.text('Не удалось проверить оплату'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Проверяем оплату…'), findsOneWidget);
    await pumpSeconds(tester, 20);
    await tester.tap(find.text('Открыть кошелёк'));
    await expectLanded(tester, '/paid/wallet');
  });

  testWidgets('stars purchase cancel returns to the wallet or home', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/paid/cancel',
      child: const StarsCheckoutCancelScreen(),
    );
    await tester.tap(find.text('Вернуться в кошелёк'));
    await expectLanded(tester, '/paid/wallet');
  });

  testWidgets('subscription plans show a price error with a retry', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/subscription',
      child: const SubscriptionScreen(),
    );
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось загрузить цены'), findsOneWidget);
    await tester.ensureVisible(find.text('Повторить'));
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось загрузить цены'), findsOneWidget);
    await tester.ensureVisible(find.text('Написать в поддержку'));
    await tester.tap(find.text('Написать в поддержку'));
    await expectLanded(tester, '/support');
    await pumpSeconds(tester, 2);
  });

  testWidgets('new reel without a session goes to sign in', (tester) async {
    await pumpRoute(
      tester,
      location: '/community/upload',
      child: const CommunityUploadScreen(),
    );
    await expectLanded(tester, '/login');
  });

  testWidgets('sign in validates fields and links onward', (tester) async {
    await pumpRoute(tester, location: '/login', child: const LoginScreen());
    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.byType(SnackBar), findsWidgets);
    await tester.tap(find.text('Забыли пароль?'));
    await expectLanded(tester, '/forgot-password');
    await pumpSeconds(tester, 5);

    await pumpRoute(tester, location: '/login', child: const LoginScreen());
    await tester.ensureVisible(find.text('Зарегистрироваться'));
    await tester.tap(find.text('Зарегистрироваться'));
    await expectLanded(tester, '/register');
    await pumpSeconds(tester, 2);
  });

  testWidgets('sign up validates fields and returns to sign in', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/register',
      child: const RegisterScreen(),
    );
    await tester.ensureVisible(find.text('Зарегистрироваться'));
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pump();
    expect(find.byType(SnackBar), findsWidgets);
    await tester.ensureVisible(find.text('Войти'));
    await tester.tap(find.text('Войти'));
    await expectLanded(tester, '/login');
    await pumpSeconds(tester, 5);
  });
}
