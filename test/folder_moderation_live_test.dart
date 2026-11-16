import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/channels/presentation/channel_giveaways_screen.dart';
import 'package:han_eat/features/channels/presentation/channel_info_screen.dart';
import 'package:han_eat/features/channels/presentation/channel_settings_screen.dart';
import 'package:han_eat/features/channels/presentation/channel_subscribers_screen.dart';
import 'package:han_eat/features/channels/presentation/channel_suggested_posts_screen.dart';
import 'package:han_eat/features/channels/presentation/create_channel_post_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_folder_edit_screen.dart';
import 'package:han_eat/features/chat/presentation/chat_group_moderation_log_screen.dart';
import 'package:han_eat/features/creator/presentation/promoted_posts_screen.dart';
import 'package:han_eat/features/moderation/presentation/miniapps_moderation_screen.dart';
import 'package:han_eat/features/moderation/presentation/moderation_queue_screen.dart';
import 'package:han_eat/features/profile/presentation/follow_list_screen.dart';
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

  testWidgets('group moderation log offers a retry when the chat fails', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/thread/5/moderation',
      child: const ChatGroupModerationLogScreen(conversationId: 5),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    expect(find.text('Чат не найден'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('История модерации'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('opening a folder by id can retry and return to chats', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/folders/4',
      child: const ChatFolderEditScreen(folderId: 4),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Не удалось открыть папку'), findsOneWidget);
    expect(find.text('Папка не найдена'), findsNothing);
    await tester.tap(find.text('Повторить'));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a new folder asks for a name and reports a failed save', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/chats/folders/new',
      child: const ChatFolderEditScreen(),
    );
    expect(find.text('Новая папка'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pump();
    expect(find.text('Введите название папки'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Семья');
    await tester.tap(find.text('Готово'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Новая папка'), findsOneWidget);
    expect(find.byType(SnackBar), findsWidgets);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/chats');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('channel settings error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/channel/1/settings',
      child: const ChannelSettingsScreen(channelId: 1, channelName: 'Новости'),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить настройки'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Назад'));
    await expectLanded(tester, '/chats');
  });

  testWidgets('channel info error can retry and return to chats', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/1/info',
      child: const ChannelInfoScreen(channelId: 1),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('К чатам'));
    await expectLanded(tester, '/chats');
  });

  testWidgets('subscribers error can retry and return to the channel', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/1/subscribers',
      child: const ChannelSubscribersScreen(
        channelId: 1,
        channelName: 'Новости',
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить подписчиков'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('К каналу'));
    await expectLanded(tester, '/channel/1');
  });

  testWidgets('suggested post sheet can be cancelled and the list retried', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/1/suggested',
      child: const ChannelSuggestedPostsScreen(
        channelId: 1,
        channelName: 'Новости',
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.byTooltip('Предложить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Предложить пост'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Отправить'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Предложения · Новости'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/channel/1');
  });

  testWidgets('giveaways error can retry and return to the channel', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channels/1/giveaways',
      child: const ChannelGiveawaysScreen(
        channelId: 1,
        channelName: 'Новости',
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Розыгрыши · Новости'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/channel/1');
  });

  testWidgets('followers error can retry and return to the profile', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/profile/followers',
      child: const FollowListScreen(
        userId: 3,
        type: FollowListType.followers,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.text('К профилю'));
    await expectLanded(tester, '/profile');
  });

  testWidgets('promoted posts error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/creator/promoted',
      child: const PromotedPostsScreen(),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Не удалось загрузить'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('К инструментам'));
    await expectLanded(tester, '/creator/tools');
  });

  testWidgets('moderation queue error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/moderation',
      child: const ModerationQueueScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Не удалось загрузить очередь'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Очередь модерации'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/moderation-dashboard');
  });

  testWidgets('mini-app moderation filter and retry can leave', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/moderation/miniapps',
      child: const MiniAppsModerationScreen(),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Ошибка загрузки'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('На проверке'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Модерация мини-приложений'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/moderation-dashboard');
  });

  testWidgets('an empty channel post asks for text and can be cancelled', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/channel/3/post/new',
      child: const CreateChannelPostScreen(channelId: 3),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
    await tester.pump();
    expect(find.text('Добавьте текст, фото или видео'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await expectLanded(tester, '/channel/3');
  });
}
