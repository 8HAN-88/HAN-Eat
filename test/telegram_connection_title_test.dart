import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/widgets/telegram_connection_chrome.dart';

void main() {
  testWidgets('section title keeps fallback when the connection is healthy',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TelegramConnectionAwareTitle(fallback: 'Сообщения'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Сообщения'), findsOneWidget);
    expect(find.text('Обновление…'), findsNothing);
    expect(find.text('Соединение…'), findsNothing);
  });

  testWidgets('empty fallback hides the title when there is no status',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TelegramConnectionAwareTitle(fallback: ''),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Text), findsNothing);
  });
}
