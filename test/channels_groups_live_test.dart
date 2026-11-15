import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/channels/presentation/channel_search_screen.dart';
import 'package:han_eat/features/channels/presentation/channels_management_screen.dart';
import 'package:han_eat/features/channels/presentation/create_channel_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_create_group_screen.dart';
import 'package:han_eat/features/comments/presentation/comments_screen.dart';
import 'package:han_eat/models/post_model.dart';
import 'package:han_eat/features/creator/presentation/scheduled_posts_screen.dart';
import 'package:han_eat/features/moderation/presentation/moderation_dashboard_screen.dart';
import 'package:han_eat/features/monetization/presentation/donation_screen.dart';
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

  test('channel slug keeps a Russian name and strips punctuation', () {
    expect(channelSlugFromName('Новости и обзоры'), 'novosti_i_obzory');
    expect(channelSlugFromName('Новости!!!'), 'novosti');
    expect(channelSlugFromName('Hello!!'), 'hello');
    expect(channelSlugFromName('ъь'), isEmpty);
    expect(channelSlugFromName('a' * 80).length, lessThanOrEqualTo(50));
  });

  testWidgets('creating a channel accepts a Russian name and its switches', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/create-channel',
      child: const CreateChannelScreen(),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Новости и обзоры');
    await tester.pump();
    expect(find.text('novosti_i_obzory'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Выбрать аватар'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Создать канал'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Платный канал'));
    await tester.tap(find.text('Платный канал'));
    await tester.pump();
    expect(find.text('Цена в звёздах в месяц'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Создать канал'));
    await tester.tap(find.widgetWithText(FilledButton, 'Создать канал'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Войдите'), findsWidgets);

    await tester.ensureVisible(find.text('Публичный канал'));
    await tester.tap(find.text('Публичный канал'));
    await expectLanded(tester, '/subscription/flex');
  });

  testWidgets('channel catalog filters retry and can leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/channels/management',
      child: const ChannelsManagementScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Новые'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Категория'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Новости').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Ещё'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Мин. подписчиков'), findsOneWidget);
    await tester.tap(find.text('Применить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Управление каналами'), findsOneWidget);

    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/chats');
  });

  testWidgets('channel search retry and clear stay on the screen', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/1/search',
      child: const ChannelSearchScreen(channelId: 1),
    );
    expect(find.text('Поиск по каналу'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'новости');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Повторить'), findsWidgets);
    await tester.tap(find.text('Повторить').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Очистить'));
    await tester.pump();
    expect(find.text('Поиск по каналу'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await expectLanded(tester, '/channel/1');
  });

  testWidgets('new group stays disabled until people are chosen', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/new-group',
      child: const ChatCreateGroupScreen(),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Повторить'), findsOneWidget);
    final create = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Создать'),
    );
    expect(create.onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Друзья');
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Создать')).onPressed,
      isNull,
    );
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Новая группа'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('comments error can retry and return to the post', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/post/7/comments',
      child: CommentsScreen(
        postId: 7,
        post: PostModel(
          id: 7,
          type: 'text',
          status: 'published',
          createdAt: DateTime.utc(2026, 1, 1),
          userId: 1,
          likesCount: 0,
          commentsCount: 0,
          repostsCount: 0,
          viewsCount: 0,
          isLiked: false,
          reactions: const [
            PostReactionChip(emoji: '❤️', count: 1, reactedByMe: false),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить комментарии'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('К посту'));
    await expectLanded(tester, '/post/7');
  });

  testWidgets('scheduled posts error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/creator/scheduled-posts',
      child: const ScheduledPostsScreen(),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('К инструментам'));
    await expectLanded(tester, '/creator/tools');
  });

  testWidgets('moderation error can refresh and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/moderation-dashboard',
      child: const ModerationDashboardScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Модерация'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/settings');
  });

  testWidgets('donation amount chips change the send button', (tester) async {
    await pumpRoute(
      tester,
      location: '/donate',
      child: const DonationScreen(recipientId: 4, recipientName: 'Автор'),
    );
    expect(find.text('Отправить 100 ★'), findsOneWidget);
    await tester.tap(find.text('250 ★'));
    await tester.pump();
    expect(find.text('Отправить 250 ★'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Спасибо');
    await tester.pump();
    expect(find.text('Спасибо'), findsOneWidget);
    expect(find.text('Поддержать автора'), findsOneWidget);
  });
}
