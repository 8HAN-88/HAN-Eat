import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/widgets/web_dom_video_layer.dart';

void main() {
  test('DOM reel layer is not preferred on VM/mobile builds', () {
    expect(WebDomVideoLayer.isPreferred, isFalse);
    expect(WebDomVideoLayer.isSupported, isFalse);
  });

  test('DOM reel layer stays behind the Flutter view by default', () {
    const layer = WebDomVideoLayer(urls: ['https://cdn.example/a.mp4']);
    expect(layer.behindCanvas, isTrue);
    expect(layer.revealInsets, EdgeInsets.zero);
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
