import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/services/feed_api_cache.dart';

import 'helpers/e2e_session.dart';

/// E2E: лента, кеш офлайн, подписка, legacy redirect (нужен backend :5001).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment(
    'HANEAT_API_BASE',
    defaultValue: 'http://127.0.0.1:5001',
  );

  late E2eSession session;

  group('Feed & subscription E2E', () {
    setUpAll(() async {
      session = await E2eSession.registerFresh(baseUrl: baseUrl);
    });

    testWidgets('feed loads or shows empty/error without crash', (tester) async {
      await session.pumpStartup(tester);
      await session.signInAndSkipOnboarding(tester);

      session.router(tester).go(FeedRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 20));

      expect(find.text('Главная'), findsWidgets);

      final hasPosts = find.byType(Scrollable).evaluate().isNotEmpty;
      final hasEmpty = find.text('Пока нет постов').evaluate().isNotEmpty;
      final hasError = find.text('Не удалось загрузить ленту').evaluate().isNotEmpty;
      final hasRetry = find.text('Повторить').evaluate().isNotEmpty;

      expect(
        hasPosts || hasEmpty || hasError,
        isTrue,
        reason: 'Feed should show content, empty, or error state',
      );
      if (hasError) {
        expect(hasRetry, isTrue);
      }
    });

    testWidgets('feed API cache round-trip via HTTP feed', (tester) async {
      final token = await session.accessToken();
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('$baseUrl/api/v1/feed?limit=5'),
        );
        req.headers.set('Authorization', 'Bearer $token');
        final res = await req.close();
        expect(res.statusCode, 200);
        final body =
            jsonDecode(await res.transform(utf8.decoder).join()) as Map;
        final items = (body['items'] as List<dynamic>? ?? const [])
            .map((e) => PostModel.fromJson(e as Map<String, dynamic>))
            .toList();

        if (items.isNotEmpty) {
          await FeedApiCache.save('rec_all', items);
          final loaded = await FeedApiCache.load('rec_all');
          expect(loaded.length, items.length);
          expect(loaded.first.id, items.first.id);
        }
      } finally {
        client.close();
      }
    });

    testWidgets('subscription status API returns entitlements', (tester) async {
      final token = await session.accessToken();
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('$baseUrl/api/v1/subscriptions/status'),
        );
        req.headers.set('Authorization', 'Bearer $token');
        final res = await req.close();
        expect(res.statusCode, 200);
        final body =
            jsonDecode(await res.transform(utf8.decoder).join()) as Map;
        expect(body.containsKey('subscription_type'), isTrue);
        expect(body.containsKey('entitlements'), isTrue);
      } finally {
        client.close();
      }
    });

    testWidgets('/community redirects to main feed', (tester) async {
      await session.pumpStartup(tester);
      await session.signInAndSkipOnboarding(tester);

      session.router(tester).go(CommunityRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('Главная'), findsWidgets);
    });
  });
}
