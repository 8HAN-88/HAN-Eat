import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_open_anchor.dart';

void main() {
  testWidgets('opens at the last messages after the first layout',
      (tester) async {
    final scroll = ChatThreadScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView.builder(
              controller: scroll,
              itemCount: 80,
              itemBuilder: (_, i) => SizedBox(
                height: 48,
                child: Text('m$i'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(scroll.hasClients, isTrue);
    expect(scroll.position.maxScrollExtent, greaterThan(100));
    expect(
      scroll.offset,
      closeTo(scroll.position.maxScrollExtent, 2),
    );
  });
}
