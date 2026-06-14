import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:han_eat/app/app.dart';

void main() {
  testWidgets('App boots MaterialApp shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HanEatApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
