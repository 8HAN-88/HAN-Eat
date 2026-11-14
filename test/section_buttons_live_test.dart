import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/feed/presentation/main_feed_screen.dart';
import 'package:han_eat/features/miniapps/presentation/miniapps_catalog_screen.dart';
import 'package:han_eat/features/notifications/presentation/notifications_screen.dart';
import 'package:han_eat/features/profile/presentation/profile_screen.dart';
import 'package:han_eat/features/reels/presentation/reels_feed_screen.dart';
import 'package:han_eat/features/search/presentation/search_screen.dart';
import 'package:han_eat/features/settings/presentation/settings_screen.dart';
import 'package:han_eat/features/stories/presentation/stories_hub_screen.dart';
import 'package:han_eat/features/support/presentation/support_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сеть в этих тестах сразу отказывает, чтобы кнопки проверялись без продакшена.
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
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
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
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('opened:$path'), findsWidgets);
  }

  testWidgets('settings buttons open their sections', (tester) async {
    await pumpRoute(
      tester,
      location: '/settings',
      child: const SettingsScreen(),
    );
    expect(find.text('Настройки'), findsOneWidget);

    final settingsList = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final choice in ['Светлая', 'Тёмная', 'Полночь', 'Системная']) {
      tester.state<ScrollableState>(settingsList).position.jumpTo(0);
      await tester.pump();
      await tester.tap(find.text(choice));
      await tester.pump();
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme_mode'), 'system');

    await tester.scrollUntilVisible(
      find.text('Вибро-отсчёт медленного режима'),
      300,
      scrollable: settingsList,
    );
    await tester.tap(find.text('Вибро-отсчёт медленного режима'));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              'Вибро-отсчёт медленного режима',
            ),
          )
          .value,
      isFalse,
    );
    expect(
      prefs.getBool('chat_thread_slow_mode_countdown_haptics_v1'),
      isFalse,
    );

    await tester.tap(find.text('Автоповтор при лимитах'));
    await tester.pump();

    await tester.ensureVisible(find.text('Время в сети'));
    await tester.tap(find.text('Время в сети'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Кто видит время в сети'), findsOneWidget);
    await tester.tap(find.text('Никто'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Плата за сообщения'));
    await tester.tap(find.text('Плата за сообщения'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Отмена').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    const tiles = <String, String>{
      'Настройки профиля': '/profile-auth',
      'Аккаунт и безопасность': '/account-security',
      'Входящие': '/notifications',
      'Настройки уведомлений': '/settings/notifications',
      'Поддержка': '/support',
      'Подписка': '/subscription/flex',
      'Реферальная программа': '/settings/referral',
      'Звёзды и кошелёк': '/paid/wallet',
      'Мои боты': '/bots/my',
      'Заказать рекламу': '/ads',
      'Доп. реклама за долю': '/settings/extra-ads',
      'Поддержка и безопасность': '/support-security',
      'Чёрный список': '/settings/blocked',
      'Резервная копия': '/backup',
    };
    for (final entry in tiles.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await expectOpened(tester, entry.value);
      expect(find.text('Настройки'), findsOneWidget);
    }

    await tester.ensureVisible(find.text('О приложении'));
    await tester.tap(find.text('О приложении'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HanWe'), findsWidgets);
    expect(find.text('Условия использования'), findsOneWidget);
    expect(find.text('Конфиденциальность'), findsOneWidget);
    await tester.tap(find.text('Условия использования'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Условия использования'), findsOneWidget);
    await tester.tap(find.text('Конфиденциальность'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (find.text('Close').evaluate().isNotEmpty) {
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Настройки'), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/feed');
  });

  testWidgets('stories hub buttons open create and close friends', (tester) async {
    await pumpRoute(
      tester,
      location: '/stories',
      child: const StoriesHubScreen(),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Моменты'), findsOneWidget);

    await tester.tap(find.byTooltip('Близкие друзья'));
    await expectOpened(tester, '/close-friends');

    await tester.tap(find.byTooltip('Создать сторис'));
    await expectOpened(tester, '/stories/create');

    final create = find.text('Создать сторис');
    if (create.evaluate().isNotEmpty) {
      await tester.tap(create);
      await expectOpened(tester, '/stories/create');
    }
    await tester.tap(find.text('Сторис'));
    await expectOpened(tester, '/stories/create');

    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/feed');
  });

  testWidgets('feed header buttons open stories and wallet', (tester) async {
    await pumpRoute(
      tester,
      location: '/feed',
      child: const MainFeedScreen(),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Моменты').hitTestable());
    await expectOpened(tester, '/stories');
    await tester.tap(find.byTooltip('Звёзды и кошелёк').hitTestable());
    await expectOpened(tester, '/paid/wallet');
  });

  testWidgets('search tabs, filter, and back respond', (tester) async {
    await pumpRoute(
      tester,
      location: '/search',
      child: const SearchScreen(),
    );
    expect(find.text('Поиск'), findsOneWidget);
    for (final tab in ['Посты', 'Люди', 'Каналы', 'Все']) {
      await tester.tap(find.text(tab));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pump();
    expect(find.text('Фильтры'), findsOneWidget);
    await tester.tap(find.text('Сбросить'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'han');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(find.text('han'), findsNothing);

    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/feed');
  });

  testWidgets('support buttons validate and open subscription', (tester) async {
    await pumpRoute(
      tester,
      location: '/support',
      child: const SupportScreen(),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Поддержка'), findsOneWidget);

    await tester.ensureVisible(find.text('Приоритетная поддержка'));
    await tester.tap(find.text('Приоритетная поддержка'));
    await expectOpened(tester, '/subscription/flex');

    await tester.ensureVisible(find.text('Запросить отмену подписки'));
    await tester.tap(find.text('Запросить отмену подписки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Отмена подписки'), findsWidgets);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Отправить обращение'));
    await tester.tap(find.text('Отправить обращение'));
    await tester.pump();
    expect(find.text('Пожалуйста, укажите тему'), findsOneWidget);

    await tester.tap(find.byType(BackButton).first);
    await expectLanded(tester, '/settings');
  });

  testWidgets('notification error buttons retry and return to the feed', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      location: '/notifications',
      child: const NotificationsScreen(),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Уведомления'), findsOneWidget);

    await tester.tap(find.text('К ленте'));
    await expectLanded(tester, '/feed');
  });

  testWidgets('reels empty state retry button stays on screen', (tester) async {
    await pumpRoute(
      tester,
      location: '/reels',
      child: const ReelsFeedScreen(),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Войти'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    await expectLanded(tester, '/login');
  });

  testWidgets('mini apps more menu opens my bots', (tester) async {
    await pumpRoute(
      tester,
      location: '/mini-apps',
      child: const MiniAppsCatalogScreen(),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Ещё').hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Мои боты'), findsOneWidget);
    await tester.tap(find.text('Мои боты'));
    await expectOpened(tester, '/bots/my');
    expect(find.byTooltip('Ещё'), findsWidgets);
  });

  testWidgets('logged out profile offers a sign-in button', (tester) async {
    await pumpRoute(
      tester,
      location: '/profile',
      child: const ProfileScreen(),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Войдите в аккаунт'), findsOneWidget);
    await tester.tap(find.text('Войти'));
    await expectLanded(tester, '/login');
  });

  testWidgets('another profile error can retry and leave', (tester) async {
    await pumpRoute(
      tester,
      location: '/profile',
      child: const ProfileScreen(userId: 42),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Назад'));
    await expectLanded(tester, '/feed');
  });
}
