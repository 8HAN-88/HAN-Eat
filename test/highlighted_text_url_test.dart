import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/widgets/highlighted_text.dart';

void main() {
  testWidgets('markup does not split a URL that contains underscores',
      (tester) async {
    const url = 'https://haneat.app/reel/28?ref=hello_world';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedText(
            text: 'смотри $url конец',
            style: const TextStyle(color: Colors.white),
            parseMarkup: true,
            onUrlTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining(url), findsOneWidget);
  });
}
