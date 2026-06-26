import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/app/bootstrap.dart';
import 'package:han_eat/app/router_keys.dart';
import 'package:han_eat/app/startup_shell.dart';
import 'package:han_eat/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Общие шаги E2E: bootstrap UI, онбординг, вход.
class E2eSession {
  E2eSession({
    required this.baseUrl,
    required this.email,
    required this.password,
  });

  final String baseUrl;
  final String email;
  final String password;

  static Future<E2eSession> registerFresh({
    String baseUrl = 'http://127.0.0.1:5001',
  }) async {
    final email = 'e2e${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'password123';
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
    return E2eSession(baseUrl: baseUrl, email: email, password: password);
  }

  Future<void> pumpStartup(WidgetTester tester) async {
    await bootstrapEarly();
    await tester.pumpWidget(const ProviderScope(child: StartupShell()));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('Запуск…').evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle(const Duration(seconds: 15));
  }

  Future<void> signInAndSkipOnboarding(WidgetTester tester) async {
    await AuthService.instance.signInWithEmail(email, password);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await tester.pumpAndSettle(const Duration(seconds: 2));

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
  }

  GoRouter router(WidgetTester tester) {
    final ctx = hanEatRootNavigatorKey.currentContext;
    expect(ctx, isNotNull, reason: 'No navigator context');
    return GoRouter.of(ctx!);
  }

  Future<String> accessToken() async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse('$baseUrl/api/v1/auth/login'),
      );
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({'email': email, 'password': password}));
      final res = await req.close();
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      return body['token'] as String;
    } finally {
      client.close();
    }
  }
}
