import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/auth/presentation/confirm_email_change_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_invite_join_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_media_gallery_screen.dart';
import 'package:han_eat/features/chat/presentation/saved_chat_open_screen.dart';
import 'package:han_eat/features/chat/presentation/sticker_pack_manage_screen.dart';
import 'package:han_eat/features/chat/presentation/sticker_pack_preview_screen.dart';
import 'package:han_eat/features/chat/presentation/username_deep_link_screen.dart';
import 'package:han_eat/features/legal/presentation/legal_consent_screen.dart';
import 'package:han_eat/features/settings/presentation/creator_revenue_screen.dart';
import 'package:han_eat/features/settings/presentation/paid_message_exceptions_screen.dart';
import 'package:han_eat/features/settings/presentation/star_invoice_pay_screen.dart';
import 'package:han_eat/features/settings/presentation/subscription_cancel_screen.dart';
import 'package:han_eat/features/stories/presentation/story_viewer_screen.dart';
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

  testWidgets('story link offers a retry when the moment fails to open', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/stories/4',
      child: const StoryViewerLoaderScreen(storyId: 4),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть момент'), findsOneWidget);
    expect(find.text('Сторис не найдена'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть момент'), findsOneWidget);
    await tester.tap(find.text('К моментам'));
    await expectLanded(tester, '/stories');
  });

  testWidgets('sticker pack management names a failed open', (tester) async {
    await pumpRoute(
      tester,
      location: '/stickers/3',
      child: const StickerPackManageScreen(packId: 3),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось открыть стикерпак'), findsOneWidget);
    expect(find.text('Стикерпак не найден'), findsNothing);
    expect(find.text('Необходим вход в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось открыть стикерпак'), findsOneWidget);
    await tester.tap(find.text('Назад'));
    await expectLanded(tester, '/chats');
  });

  testWidgets('sticker pack preview names a failed open', (tester) async {
    await pumpRoute(
      tester,
      location: '/addstickers/han',
      child: const StickerPackPreviewScreen(slug: 'han'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось открыть стикерпак'), findsOneWidget);
    expect(find.text('Пак не найден'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Назад'));
    await expectLanded(tester, '/chats');
  });

  testWidgets('saved chat stays on screen and can retry', (tester) async {
    await pumpRoute(
      tester,
      location: '/chats/saved',
      child: const SavedChatOpenScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть избранное'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть избранное'), findsOneWidget);
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('chat media gallery retries and returns to the thread', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/thread/6/media',
      child: const ChatMediaGalleryScreen(conversationId: 6),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Фото'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byType(BackButton));
    await expectLanded(tester, '/chats/thread/6');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('paid message exceptions can retry and open search', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/settings/paid-exceptions',
      child: const PaidMessageExceptionsScreen(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Поиск по имени или @ник'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'анна');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsWidgets);
    await tester.tap(find.text('Повторить').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tapAt(const Offset(450, 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(BackButton));
    await expectLanded(tester, '/settings');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('username link reports a failure and returns to chats', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/u/anna',
      child: const UsernameDeepLinkScreen(username: 'anna'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('group invite without a session goes to sign in', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chat-invite/abc',
      child: const ChatInviteJoinScreen(token: 'abc'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLanded(tester, '/login');
  });

  testWidgets('creator revenue error can refresh and return', (tester) async {
    await pumpRoute(
      tester,
      location: '/paid/revenue',
      child: const CreatorRevenueScreen(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось загрузить доходы'), findsOneWidget);
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось загрузить доходы'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Не удалось загрузить доходы'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await expectLanded(tester, '/creator/tools');
  });

  testWidgets('star invoice error can retry and return to the wallet', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/paid/invoices/4',
      child: const StarInvoicePayScreen(invoiceId: 4),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('К кошельку звёзд'));
    await expectLanded(tester, '/paid/wallet');
  });

  testWidgets('legal consent stays usable when documents fail to load', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/legal-consent',
      child: const LegalConsentScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Обновили условия'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.ensureVisible(find.text('Выйти из аккаунта'));
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Принять и продолжить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Войдите в аккаунт'), findsWidgets);
    expect(find.text('Обновили условия'), findsOneWidget);
  });

  testWidgets('email change asks for a code and can return to sign in', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/confirm-email-change',
      child: const ConfirmEmailChangeScreen(),
    );
    await tester.pump();
    expect(find.text('Подтвердить'), findsOneWidget);
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(find.text('Смена почты'), findsOneWidget);
    await tester.tap(find.text('На экран входа'));
    await expectLanded(tester, '/login');
  });

  testWidgets('cancelled checkout can return to the plan or the feed', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/subscription/cancel',
      child: const SubscriptionCancelScreen(),
    );
    await tester.tap(find.text('Вернуться к подписке'));
    await expectLanded(tester, '/subscription/flex');

    await pumpRoute(
      tester,
      location: '/subscription/cancel',
      child: const SubscriptionCancelScreen(),
    );
    await tester.tap(find.text('На главную'));
    await expectLanded(tester, '/feed');
  });
}
