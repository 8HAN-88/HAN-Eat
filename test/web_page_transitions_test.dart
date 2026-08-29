import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/core/theme/web_page_transitions.dart';

void main() {
  testWidgets('web fade transition covers the previous route', (tester) async {
    final animation = AlwaysStoppedAnimation<double>(1);
    const builder = WebFadePageTransitionsBuilder();
    late BuildContext captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final built = builder.buildTransitions<void>(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const SizedBox(),
        settings: const RouteSettings(name: '/test'),
      ),
      captured,
      animation,
      animation,
      const ColoredBox(color: Color(0xFF0F1319), child: Text('next')),
    );

    expect(built, isA<FadeTransition>());
    await tester.pumpWidget(MaterialApp(home: built));
    expect(find.text('next'), findsOneWidget);
  });
}
