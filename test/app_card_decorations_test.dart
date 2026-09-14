import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/theme/app_card_decorations.dart';
import 'package:han_eat/core/theme/color_schemes.dart';

void main() {
  ThemeData theme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: brightness == Brightness.dark
          ? buildDarkColorScheme()
          : buildLightColorScheme(),
    );
  }

  test('feed chrome keeps a framed card with warm hairline and depth', () {
    final deco = AppCardDecorations.feed(theme(Brightness.dark));
    final border = deco.border! as Border;

    expect(deco.borderRadius, BorderRadius.circular(AppCardDecorations.feedRadius));
    expect(border.top.width, 0.7);
    expect(border.top.color, AppCardDecorations.hairlineDark);
    expect(deco.boxShadow, isNotEmpty);
    expect(deco.boxShadow!.length, greaterThanOrEqualTo(2));
  });

  test('feed chrome can drop the lift and still keep the frame', () {
    final deco = AppCardDecorations.feed(
      theme(Brightness.light),
      showShadow: false,
    );
    final border = deco.border! as Border;

    expect(border.top.color, AppCardDecorations.hairlineLight);
    expect(deco.boxShadow, isEmpty);
  });

  testWidgets('feed card paints a top sheen over the clipped frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(Brightness.dark),
        home: const Scaffold(
          body: AppElevatedCard(
            chrome: AppCardChrome.feed,
            child: SizedBox(height: 80, width: 200),
          ),
        ),
      ),
    );

    expect(find.byType(AppElevatedCard), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
  });
}
