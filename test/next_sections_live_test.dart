import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/chat/presentation/chat_archived_screen.dart';
import 'package:han_eat/features/creator/presentation/creator_tools_screen.dart';
import 'package:han_eat/features/saved/presentation/saved_posts_screen.dart';
import 'package:han_eat/features/settings/presentation/close_friends_screen.dart';
import 'package:han_eat/features/settings/presentation/star_gifts_inventory_screen.dart';
import 'package:han_eat/features/settings/presentation/two_factor_setup_screen.dart';
import 'package:han_eat/features/stories/presentation/story_camera_screen.dart';
import 'package:han_eat/features/subscription/presentation/flex_constructor_screen.dart';
import 'package:han_eat/features/subscription/presentation/flex_shop_screen.dart';
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

  testWidgets('saved posts without a session offer sign in', (tester) async {
    await pumpRoute(
      tester,
      location: '/saved-posts',
      child: const SavedPostsScreen(),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    await expectLanded(tester, '/login');
  });

  testWidgets('story gallery buttons stay on the screen and can leave', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/stories/create',
      child: const StoryCameraScreen(),
    );
    expect(find.text('Создать сторис'), findsOneWidget);
    await tester.tap(find.text('Фото из галереи'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Создать сторис'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Видео из галереи (до 30 сек)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Создать сторис'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/stories');
  });

  testWidgets('two-factor error can retry and return to security', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/two-factor-setup',
      child: const TwoFactorSetupScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Двухфакторная защита'), findsOneWidget);
    await tester.tap(find.text('К безопасности'));
    await expectLanded(tester, '/account-security');
  });

  testWidgets('close friends error can retry and return', (tester) async {
    await pumpRoute(
      tester,
      location: '/close-friends',
      child: const CloseFriendsScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Близкие друзья'), findsOneWidget);
    await tester.tap(find.text('К настройкам'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('flex shop error opens the subscription and leaves', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/subscription/flex/shop',
      child: const FlexShopScreen(),
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.workspace_premium_outlined));
    await expectOpened(tester, '/subscription/flex');
    expect(find.text('Все возможности'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/subscription/flex');
  });

  testWidgets('flex constructor error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/subscription/flex/constructor',
      child: const FlexConstructorScreen(),
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Настроить подписку'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/subscription/flex');
  });

  testWidgets('creator tools error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/creator/tools',
      child: const CreatorToolsScreen(),
    );
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.tap(find.text('К настройкам'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('gift inventory error opens the showcase and leaves', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/paid/gifts',
      child: const StarGiftsInventoryScreen(),
    );
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Витрина'));
    await expectOpened(tester, '/paid/gifts/marketplace');
    expect(find.text('Мои подарки'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/settings');
  });

  testWidgets('archive error can retry and return to chats', (tester) async {
    await pumpRoute(
      tester,
      location: '/chats/archived',
      child: const ChatArchivedScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });
}
