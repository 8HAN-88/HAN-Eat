import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/app/invalid_link_screen.dart';
import 'package:han_eat/app/web_session_landing_screen.dart';
import 'package:han_eat/features/analytics/presentation/analytics_screen.dart';
import 'package:han_eat/features/calls/presentation/incoming_call_screen.dart';
import 'package:han_eat/features/feed/presentation/new_feed_screen.dart';
import 'package:han_eat/features/settings/application/subscription_status_provider.dart';
import 'package:han_eat/services/call_service.dart';
import 'package:han_eat/services/subscription_service.dart';
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

SubscriptionStatusResponse _status(Map<String, bool> entitlements) {
  return SubscriptionStatusResponse(
    isPlus: entitlements.isNotEmpty,
    isActive: entitlements.isNotEmpty,
    subscriptionType: entitlements.isEmpty ? 'free' : 'flex',
    entitlements: entitlements,
  );
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
    List<Override> overrides = const [],
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
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
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

  testWidgets('analytics without a status can retry and leave', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/analytics',
      child: const AnalyticsScreen(),
    );
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось загрузить статус'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось загрузить статус'), findsOneWidget);
    await tester.tap(find.text('К инструментам'));
    await expectLanded(tester, '/creator/tools');
  });

  testWidgets('analytics upsell opens creator level', (tester) async {
    await pumpRoute(
      tester,
      location: '/analytics',
      child: const AnalyticsScreen(),
      overrides: [
        subscriptionStatusProvider.overrideWith((ref) async => _status({})),
      ],
    );
    await pumpSeconds(tester, 1);
    expect(find.text('Аналитика для авторов'), findsOneWidget);
    await tester.tap(find.text('Открыть уровень 16'));
    await expectLanded(tester, '/subscription/flex');
  });

  testWidgets('profile analytics error can retry, change period and leave', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/analytics',
      child: const AnalyticsScreen(),
      overrides: [
        subscriptionStatusProvider.overrideWith(
          (ref) async => _status({'creator_analytics': true}),
        ),
      ],
    );
    await pumpSeconds(tester, 3);
    expect(find.text('Аналитика профиля'), findsOneWidget);
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await pumpSeconds(tester, 3);
    expect(find.text('Не удалось загрузить'), findsOneWidget);

    await tester.tap(find.text('30 дн'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('7 дней').last);
    await pumpSeconds(tester, 3);
    expect(find.text('7 дн'), findsOneWidget);
    expect(find.text('Не удалось загрузить'), findsOneWidget);

    await tester.tap(find.text('К инструментам'));
    await expectLanded(tester, '/creator/tools');
  });

  testWidgets('post analytics error returns to the post', (tester) async {
    await pumpRoute(
      tester,
      location: '/analytics/post/5',
      child: const AnalyticsScreen(postId: 5),
      overrides: [
        subscriptionStatusProvider.overrideWith(
          (ref) async => _status({'creator_analytics': true}),
        ),
      ],
    );
    await pumpSeconds(tester, 3);
    expect(find.text('Аналитика поста'), findsOneWidget);
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('К посту'));
    await expectLanded(tester, '/post/5');
  });

  testWidgets('broken link goes home from the button and the back arrow', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/bad',
      child: const InvalidLinkScreen(),
    );
    expect(find.text('Неверная или устаревшая ссылка'), findsOneWidget);
    await tester.tap(find.text('На главную'));
    await expectLanded(tester, '/feed');

    await pumpRoute(
      tester,
      location: '/bad',
      child: const InvalidLinkScreen(),
    );
    await tester.tap(find.byType(BackButton));
    await expectLanded(tester, '/feed');
  });

  testWidgets('web session landing without a session goes to sign in', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/web-session',
      child: const WebSessionLandingScreen(),
    );
    await expectLanded(tester, '/login');
  });

  testWidgets('incoming call can be declined and times out by itself', (
    tester,
  ) async {
    const call = CallSessionInfo(
      id: 1,
      conversationId: 2,
      callerId: 3,
      calleeId: 4,
      media: 'audio',
      status: 'ringing',
      peerName: 'Аня',
    );
    final results = <bool?>[];

    Future<void> ring(Duration timeout) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          IncomingCallScreen(call: call, timeout: timeout),
                    ),
                  );
                  results.add(result);
                },
                child: const Text('ring'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ring'));
      await tester.pumpAndSettle();
    }

    await ring(const Duration(seconds: 30));
    expect(find.text('Аня'), findsOneWidget);
    expect(find.text('Входящий звонок'), findsOneWidget);
    await tester.tap(find.text('Отклонить'));
    await tester.pumpAndSettle();
    expect(results, [false]);

    await ring(const Duration(seconds: 3));
    expect(find.text('Аня'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Аня'), findsNothing);
    expect(results, [false, null]);
  });

  testWidgets('feed header buttons are labelled and open reels and search', (
    tester,
  ) async {
    await pumpRoute(tester, location: '/feed', child: const NewFeedScreen());
    await pumpSeconds(tester, 3);
    expect(find.byTooltip('Фильтр'), findsOneWidget);
    expect(find.byTooltip('Создать'), findsOneWidget);
    await tester.tap(find.byTooltip('Поиск'));
    await expectLanded(tester, '/search');
    await pumpSeconds(tester, 3);

    await pumpRoute(tester, location: '/feed', child: const NewFeedScreen());
    await pumpSeconds(tester, 3);
    await tester.tap(find.byTooltip('Рилсы'));
    await expectLanded(tester, '/reels');
    await pumpSeconds(tester, 3);
  });
}
