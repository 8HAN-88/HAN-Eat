import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_attach_sheet.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_message_action_overlay.dart';
import 'package:han_eat/features/chat/presentation/widgets/chat_message_selection_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> openAttach(WidgetTester tester) async {
    await tester.tap(find.text('Открыть вложения'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapDock(WidgetTester tester, String label) async {
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('attach dock buttons open their panels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_attachHarness());
    await openAttach(tester);

    expect(find.text('Фото и видео'), findsOneWidget);

    await tapDock(tester, 'GIF');
    expect(find.text('Выбрать GIF с устройства'), findsWidgets);

    await tapDock(tester, 'Файл');
    expect(find.text('Выбрать из файлов'), findsOneWidget);
    expect(find.text('Выбрать из Галереи'), findsOneWidget);

    await tapDock(tester, 'Опрос');
    expect(find.text('Новый опрос'), findsOneWidget);
    expect(find.text('Текст вопроса'), findsOneWidget);

    await tapDock(tester, 'Контакт');
    expect(find.text('Контакты'), findsOneWidget);

    await tapDock(tester, 'Гео');
    expect(find.text('Геопозиция'), findsOneWidget);

    await tapDock(tester, 'Кружок');
    expect(find.text('Записать кружок'), findsOneWidget);
    expect(
      find.text('Короткое круглое видеосообщение (до 60 сек)'),
      findsOneWidget,
    );

    await tapDock(tester, 'Стикер');
    expect(find.text('Стикеры'), findsWidgets);

    await tapDock(tester, 'Мини');
    await tester.pumpAndSettle();
    expect(find.text('Каталог мини'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('record circle button returns a video note', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_attachHarness());
    await openAttach(tester);
    await tapDock(tester, 'Кружок');
    await tester.tap(find.text('Записать кружок'));
    await tester.pumpAndSettle();

    expect(find.text('result:videoNote'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('poll send button returns the draft', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_attachHarness());
    await openAttach(tester);
    await tapDock(tester, 'Опрос');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Куда идём?');
    await tester.enterText(fields.at(2), 'В парк');
    await tester.enterText(fields.at(3), 'Домой');
    await tester.pump();

    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(find.text('result:poll'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('message menu buttons report their actions', (tester) async {
    final actions = <String>[];
    final reactions = <String>[];
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  ChatMessageActionOverlay.show(
                    context: context,
                    messageRect: const Rect.fromLTWH(40, 220, 240, 72),
                    messagePreview: const Text('Привет'),
                    quickReactions: const ['👍', '❤️'],
                    isOutgoing: true,
                    canEdit: true,
                    isPinned: false,
                    canDelete: true,
                    hasCopyableText: true,
                    canForward: true,
                    onReaction: reactions.add,
                    onAction: actions.add,
                    onExpandReactions: () => expanded = true,
                  );
                },
                child: const Text('Меню'),
              ),
            );
          },
        ),
      ),
    );

    Future<void> openAndTap(String label) async {
      await tester.tap(find.text('Меню'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final item = find.text(label);
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    for (final label in [
      'Ответить',
      'Скопировать',
      'Изменить',
      'Закрепить',
      'Переслать',
      'Поделиться',
      'Удалить',
      'Выбрать',
    ]) {
      await openAndTap(label);
    }

    expect(
      actions,
      [
        'reply',
        'copy',
        'edit',
        'pin',
        'forward',
        'share',
        'delete',
        'select',
      ],
    );

    await tester.tap(find.text('Меню'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(reactions, ['👍']);
    expect(expanded, isFalse);
  });

  testWidgets('selection toolbar buttons fire', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMessageSelectionToolbar(
            enabled: true,
            canReply: true,
            onReply: () => taps.add('reply'),
            onDelete: () => taps.add('delete'),
            onCopy: () => taps.add('copy'),
            onSaveToFavorites: () => taps.add('save'),
            onShare: () => taps.add('share'),
            onForward: () => taps.add('forward'),
          ),
        ),
      ),
    );

    for (final tooltip in [
      'Ответить',
      'Удалить',
      'Копировать',
      'В избранное',
      'Поделиться',
      'Переслать',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
    }

    expect(taps, ['reply', 'delete', 'copy', 'save', 'share', 'forward']);
  });
}

Widget _attachHarness() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await showChatAttachSheet(context);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('result:${result?.kind.name ?? 'null'}'),
                  ),
                );
              },
              child: const Text('Открыть вложения'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/mini-apps',
        builder: (_, __) => const Scaffold(body: Text('Каталог мини')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}
