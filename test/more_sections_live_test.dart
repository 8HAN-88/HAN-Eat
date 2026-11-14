import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/ads/presentation/advertiser_hub_screen.dart';
import 'package:han_eat/features/bots/presentation/my_bots_screen.dart';
import 'package:han_eat/features/chat/presentation/chats_hub_screen.dart';
import 'package:han_eat/features/referral/presentation/partner_program_screen.dart';
import 'package:han_eat/features/settings/backup_page.dart';
import 'package:han_eat/features/settings/notification_settings_page.dart';
import 'package:han_eat/features/settings/presentation/account_security_screen.dart';
import 'package:han_eat/features/settings/presentation/blocked_users_screen.dart';
import 'package:han_eat/features/settings/presentation/stars_wallet_screen.dart';
import 'package:han_eat/features/settings/presentation/support_security_screen.dart';
import 'package:han_eat/features/subscription/presentation/flex_subscription_screen.dart';
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
    await tester.binding.setSurfaceSize(const Size(900, 1400));
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

  Future<void> expectOpened(WidgetTester tester, String path) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('opened:$path'), findsWidgets);
    await tester.tap(find.byType(BackButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> expectLanded(WidgetTester tester, String path) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('opened:$path'), findsWidgets);
  }

  testWidgets('signed out chats offer sign in', (tester) async {
    await pumpRoute(tester, location: '/chats', child: const ChatsHubScreen());
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    await expectLanded(tester, '/login');
  });

  testWidgets('wallet error buttons retry and return to settings', (tester) async {
    await pumpRoute(
      tester,
      location: '/paid/wallet',
      child: const StarsWalletScreen(),
    );
    expect(find.text('Не удалось загрузить кошелёк'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Звёзды и кошелёк'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    await tester.tap(find.text('К настройкам'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('subscription error opens the shop and returns', (tester) async {
    await pumpRoute(
      tester,
      location: '/subscription/flex',
      child: const FlexSubscriptionScreen(),
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Все возможности'));
    await expectOpened(tester, '/subscription/flex/shop');
    expect(find.text('Подписка'), findsOneWidget);
    await tester.tap(find.text('К настройкам'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('ads hub buttons open a new order and support', (tester) async {
    await pumpRoute(
      tester,
      location: '/ads',
      child: const AdvertiserHubScreen(),
    );
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Написать в поддержку'));
    await expectOpened(tester, '/support');
    await tester.tap(find.text('Новая заявка').first);
    await expectOpened(tester, '/ads/new');
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/settings');
  });

  testWidgets('account security tiles and logout respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/account-security',
      child: const AccountSecurityScreen(),
    );
    expect(find.text('Аккаунт и безопасность'), findsOneWidget);
    await tester.tap(find.text('Аккаунт'));
    await expectOpened(tester, '/profile-auth');
    await tester.tap(find.text('Пароль и вход'));
    await expectOpened(tester, '/profile-auth');
    await tester.tap(find.text('Двухфакторная защита'));
    await expectOpened(tester, '/two-factor-setup');
    await tester.tap(find.text('Близкие друзья'));
    await expectOpened(tester, '/close-friends');
    await tester.ensureVisible(find.text('Завершить все сеансы'));
    await tester.tap(find.text('Завершить все сеансы'));
    await expectLanded(tester, '/login');
  });

  testWidgets('blocked list error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/settings/blocked',
      child: const BlockedUsersScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Чёрный список'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await expectLanded(tester, '/settings');
  });

  testWidgets('create bot dialog validates the name and cancels', (tester) async {
    await pumpRoute(
      tester,
      location: '/bots/my',
      child: const MyBotsScreen(),
    );
    await tester.tap(find.byTooltip('Создать бота'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Имя пользователя'), findsOneWidget);
    await tester.tap(find.text('Создать'));
    await tester.pump();
    expect(find.text('Введите имя бота'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/settings');
    await tester.pump(const Duration(seconds: 90));
  });

  testWidgets('partner program retry and back respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/settings/referral',
      child: const PartnerProgramScreen(),
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Партнёрская программа'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/settings');
  });

  testWidgets('notification settings retry and back respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/settings/notifications',
      child: const NotificationSettingsPage(),
    );
    expect(find.text('Не удалось загрузить настройки'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Настройки уведомлений'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('backup export and import buttons respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/backup',
      child: const BackupPage(),
    );
    await tester.tap(find.text('Экспорт профиля'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Войдите'), findsWidgets);
    await tester.tap(find.text('Импорт (заменить)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Резервная копия'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('support and security links and dialogs respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/support-security',
      child: const SupportSecurityScreen(),
    );
    await tester.tap(find.text('Аккаунт и безопасность'));
    await expectOpened(tester, '/account-security');
    await tester.tap(find.text('Политика конфиденциальности'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Поддержка и безопасность'), findsOneWidget);
    await tester.tap(find.text('Безопасность данных'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Понятно'), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.text('Модерация контента'));
    await tester.tap(find.text('Модерация контента'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Понятно'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.text('Пожаловаться на контент'));
    await tester.tap(find.text('Пожаловаться на контент'));
    await expectOpened(tester, '/support');
    await tester.ensureVisible(find.text('Чёрный список'));
    await tester.tap(find.text('Чёрный список'));
    await expectOpened(tester, '/settings/blocked');
    await tester.ensureVisible(find.text('Связаться с нами'));
    await tester.tap(find.text('Связаться с нами'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Поддержка и безопасность'), findsOneWidget);
    await tester.ensureVisible(find.text('Сообщить об ошибке'));
    await tester.tap(find.text('Сообщить об ошибке'));
    await expectOpened(tester, '/support');
    await tester.ensureVisible(find.text('О приложении'));
    await tester.tap(find.text('О приложении'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HanWe'), findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/settings');
  });
}
