import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_open_anchor.dart';

void main() {
  testWidgets('reversed list first frame is the latest messages',
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
              reverse: true,
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

    expect(scroll.hasClients, isTrue);
    expect(scroll.offset, lessThan(8));
    expect(find.text('m0'), findsOneWidget);
    expect(find.text('m79'), findsNothing);
  });
}
