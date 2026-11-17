import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/channels/presentation/channel_detail_screen.dart';
import 'package:han_eat/features/channels/presentation/channel_management_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_group_info_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_people_search_screen.dart';
import 'package:han_eat/features/settings/presentation/profile_auth_screen.dart';
import 'package:han_eat/features/settings/presentation/star_gifts_marketplace_screen.dart';
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

  testWidgets('group info offers a retry when the chat fails to open', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/thread/9/info',
      child: const ChatGroupInfoLoaderScreen(conversationId: 9),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть чат'), findsOneWidget);
    expect(find.text('Чат не найден'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('О группе'), findsOneWidget);
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('channel management error can retry and return', (tester) async {
    await pumpRoute(
      tester,
      location: '/channel/2/management',
      child: const ChannelManagementScreen(channelId: 2),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('К каналу'));
    await expectLanded(tester, '/channel/2');
  });

  testWidgets('channel page error can retry and return to chats', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/2',
      child: const ChannelDetailScreen(channelId: 2),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить канал'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
  });

  testWidgets('people search reports a failure and can be cleared', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/people',
      child: const ChatPeopleSearchScreen(),
    );
    expect(find.text('Найти людей'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'анна');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось найти'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Очистить'));
    await tester.pump();
    expect(find.text('Найти людей'), findsWidgets);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('gift showcase error can retry and return', (tester) async {
    await pumpRoute(
      tester,
      location: '/paid/gifts/marketplace',
      child: const StarGiftsMarketplaceScreen(),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Витрина подарков'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/paid/gifts');
  });

  testWidgets('profile without a session goes to sign in', (tester) async {
    await pumpRoute(
      tester,
      location: '/profile/edit',
      child: const ProfileAuthScreen(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLanded(tester, '/login');
  });
}
