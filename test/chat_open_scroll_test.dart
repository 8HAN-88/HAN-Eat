import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_open_anchor.dart';

void main() {
  testWidgets('first layout opens at the last messages, not the top',
      (tester) async {
    final scroll = ChatThreadScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: scroll,
            itemCount: 80,
            itemBuilder: (_, i) => SizedBox(height: 48, child: Text('m$i')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(scroll.hasClients, isTrue);
    expect(scroll.offset, greaterThan(scroll.position.maxScrollExtent - 8));
    expect(find.text('m79'), findsOneWidget);
    expect(find.text('m0'), findsNothing);
  });
}
