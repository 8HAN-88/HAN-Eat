import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/admin/presentation/admin_creator_payouts_screen.dart';
import 'package:han_eat/features/admin/presentation/admin_partner_payouts_screen.dart';
import 'package:han_eat/features/admin/presentation/admin_refund_queue_screen.dart';
import 'package:han_eat/features/admin/presentation/admin_support_tickets_screen.dart';
import 'package:han_eat/features/ads/presentation/ad_campaign_editor_screen.dart';
import 'package:han_eat/features/ads/presentation/ads_review_screen.dart';
import 'package:han_eat/features/auth/presentation/forgot_password_screen.dart';
import 'package:han_eat/features/auth/presentation/reset_password_screen.dart';
import 'package:han_eat/features/auth/presentation/two_factor_verify_screen.dart';
import 'package:han_eat/features/auth/presentation/verify_email_screen.dart';
import 'package:han_eat/features/subscription/presentation/admin_flex_features_screen.dart';
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

  Future<void> dismissSnack(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(SnackBar), findsNothing);
  }

  Future<void> walkQueue(
    WidgetTester tester, {
    required String location,
    required Widget child,
  }) async {
    await pumpRoute(tester, location: location, child: child);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/moderation-dashboard');
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('refund queue buttons respond offline', (tester) async {
    await walkQueue(
      tester,
      location: '/admin/refunds',
      child: const AdminRefundQueueScreen(),
    );
  });

  testWidgets('partner payout queue buttons respond offline', (tester) async {
    await walkQueue(
      tester,
      location: '/admin/partner-payouts',
      child: const AdminPartnerPayoutsScreen(),
    );
  });

  testWidgets('creator payout queue buttons respond offline', (tester) async {
    await walkQueue(
      tester,
      location: '/admin/creator-payouts',
      child: const AdminCreatorPayoutsScreen(),
    );
  });

  testWidgets('support ticket queue buttons respond offline', (tester) async {
    await walkQueue(
      tester,
      location: '/admin/support-tickets',
      child: const AdminSupportTicketsScreen(),
    );
  });

  testWidgets('ad review queue buttons respond offline', (tester) async {
    await walkQueue(
      tester,
      location: '/moderation/ads',
      child: const AdsReviewScreen(),
    );
  });

  testWidgets('ad campaign that fails to open can retry and leave', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/ads/5',
      child: const AdCampaignEditorScreen(campaignId: 5),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть'), findsOneWidget);
    await tester.tap(find.text('К рекламе'));
    await expectLanded(tester, '/ads');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('subscription features hide add until the catalog loads', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/admin/flex-features',
      child: const AdminFlexFeaturesScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.byTooltip('Новая функция'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/settings');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('forgot password explains a network failure', (tester) async {
    await pumpRoute(
      tester,
      location: '/forgot-password',
      child: const ForgotPasswordScreen(),
    );
    await tester.tap(find.text('Отправить письмо'));
    await tester.pump();
    expect(find.text('Введите почту'), findsWidgets);
    await dismissSnack(tester);
    await tester.enterText(find.byType(TextFormField), 'anna@example.com');
    await tester.tap(find.text('Отправить письмо'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('Отправить письмо'), findsOneWidget);
    await tester.tap(find.text('Вернуться ко входу'));
    await expectLanded(tester, '/login');
  });

  testWidgets('reset password explains a network failure', (tester) async {
    await pumpRoute(
      tester,
      location: '/reset-password',
      child: const ResetPasswordScreen(
        initialEmail: 'anna@example.com',
        initialToken: '123456',
      ),
    );
    await tester.tap(find.text('Сохранить пароль'));
    await tester.pump();
    expect(find.text('Минимум 8 символов'), findsOneWidget);
    await dismissSnack(tester);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'new-secret-1');
    await tester.enterText(fields.at(2), 'new-secret-1');
    await tester.ensureVisible(find.text('Сохранить пароль'));
    await tester.tap(find.text('Сохранить пароль'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(find.text('Сохранить пароль'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/login');
  });

  testWidgets('email verification reports a failed code and returns', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/verify-email',
      child: const VerifyEmailScreen(email: 'anna@example.com'),
    );
    expect(find.text('Подтвердить'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, '123456');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsWidgets);
    expect(find.text('Подтвердить'), findsOneWidget);
    await tester.ensureVisible(find.text('Ко входу'));
    await tester.tap(find.text('Ко входу'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await expectLanded(tester, '/login');
  });

  testWidgets('two-factor code needs six digits and can go back', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/2fa-verify',
      child: const TwoFactorVerifyScreen(
        pendingToken: 'pending',
        email: 'anna@example.com',
      ),
    );
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(find.text('Подтвердить'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/login');
  });
}
