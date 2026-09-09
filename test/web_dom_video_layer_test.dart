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

  testWidgets('overlay button still receives taps through the video layer',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: TextButton(
                onPressed: () => tapped = true,
                child: const Text('Like'),
              ),
            ),
            const Positioned.fill(
              child: WebDomVideoLayer(
                urls: ['https://cdn.example/a.mp4'],
                active: false,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Like'));
    expect(tapped, isTrue);
  });

  testWidgets('video layer is visual-only and does not take taps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.expand(
          child: WebDomVideoLayer(
            urls: ['https://cdn.example/a.mp4'],
            active: false,
          ),
        ),
      ),
    );
    expect(find.byType(IgnorePointer), findsWidgets);
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
