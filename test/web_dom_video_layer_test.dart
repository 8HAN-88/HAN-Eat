import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/widgets/web_dom_video_layer.dart';

void main() {
  test('DOM reel layer is not preferred on VM/mobile builds', () {
    expect(WebDomVideoLayer.isPreferred, isFalse);
    expect(WebDomVideoLayer.isSupported, isFalse);
  });

  testWidgets('CanvasPunchHole paints without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(child: CanvasPunchHole()),
      ),
    );
    expect(find.byType(CanvasPunchHole), findsOneWidget);
  });
}
