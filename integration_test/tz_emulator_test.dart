import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:han_eat/app/app_router.dart';
import 'package:han_eat/app/bootstrap.dart';
import 'package:han_eat/app/startup_shell.dart';
import 'package:han_eat/app/router_keys.dart';
import 'package:han_eat/features/subscription/subscription_copy.dart';
import 'package:han_eat/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// E2E на симуляторе: ТЗ подписки + Creator V2 (нужен backend :5001).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String email;
  late String password;
  const baseUrl = String.fromEnvironment(
    'HANEAT_API_BASE',
    defaultValue: 'http://127.0.0.1:5001',
  );

  group('TZ emulator E2E', () {
    setUpAll(() async {
      email = 'e2e${DateTime.now().millisecondsSinceEpoch}@example.com';
      password = 'password123';
      final api = '$baseUrl/api/v1';
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('$api/auth/register'));
        req.headers.set('Content-Type', 'application/json');
        req.write(
          jsonEncode({
            'email': email,
            'password': password,
            'name': 'E2E Test',
            'username': 'e2e${DateTime.now().millisecondsSinceEpoch % 100000}',
          }),
        );
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode >= 400) {
          throw Exception('register failed ${res.statusCode}: $body');
        }
      } finally {
        client.close();
      }
    });

    testWidgets('login → subscription → trial → creator tools', (tester) async {
      await bootstrapEarly();
      await tester.pumpWidget(
        const ProviderScope(child: StartupShell()),
      );

      // Firebase / Hive init
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.text('Запуск…').evaluate().isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle(const Duration(seconds: 15));

      // Сессия через API (redirect на /subscription без auth уводит на profile-auth).
      await AuthService.instance.signInWithEmail(email, password);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', true);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Закрыть онбординг, если prefs не успели примениться до первого кадра.
      for (var i = 0; i < 4; i++) {
        final next = find.text('Далее');
        if (next.evaluate().isEmpty) break;
        await tester.tap(next);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }
      final startBtn = find.text('Начать');
      if (startBtn.evaluate().isNotEmpty) {
        await tester.tap(startBtn);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      // Deep link style navigation via GoRouter
      final ctx = hanEatRootNavigatorKey.currentContext;
      expect(ctx, isNotNull, reason: 'No navigator context after login');
      final router = GoRouter.of(ctx!);

      router.push(SubscriptionRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 15));
      expect(find.text(SubscriptionCopy.screenTitle), findsWidgets);
      expect(find.textContaining('HanWe'), findsWidgets);

      // Trial via API then Creator tools
      final token = await _loginToken(baseUrl, email, password);
      await _startTrialPro(baseUrl, token);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      router.push(CreatorToolsRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 15));
      expect(
        find.text('Инструменты автора'),
        findsWidgets,
        reason: 'Creator tools screen',
      );
      expect(find.textContaining('Продвижение'), findsWidgets);

      router.push(ScheduledPostsRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text('Запланированные посты'), findsOneWidget);

      router.push(PromotedPostsRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text('Продвижение'), findsWidgets);

      router.push(SettingsRoute.path);
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.text(SubscriptionCopy.screenTitle), findsWidgets);
    });
  });
}

Future<String> _loginToken(String base, String email, String password) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$base/api/v1/auth/login'));
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({'email': email, 'password': password}));
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    return body['token'] as String;
  } finally {
    client.close();
  }
}

Future<void> _startTrialPro(String base, String token) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$base/api/v1/subscriptions/trial'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $token');
    req.write(jsonEncode({'product': 'pro'}));
    final res = await req.close();
    if (res.statusCode >= 400) {
      final body = await res.transform(utf8.decoder).join();
      debugPrint('trial pro skipped: ${res.statusCode} $body');
    }
  } finally {
    client.close();
  }
}
