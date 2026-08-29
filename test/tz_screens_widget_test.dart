import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:han_eat/features/creator/presentation/creator_tools_screen.dart';
import 'package:han_eat/features/creator/presentation/promoted_posts_screen.dart';
import 'package:han_eat/features/creator/presentation/scheduled_posts_screen.dart';
import 'package:han_eat/features/admin/presentation/admin_refund_queue_screen.dart';
import 'package:han_eat/features/settings/presentation/subscription_screen.dart';

/// Smoke UI: экраны ТЗ монтируются без падения (сеть в тестах не мокается).
Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('SubscriptionScreen mounts', (tester) async {
    await tester.pumpWidget(
      _wrap(const SubscriptionScreen()),
    );
    await tester.pump();
    expect(find.text('Моя подписка'), findsWidgets);
  });

  testWidgets('CreatorToolsScreen mounts', (tester) async {
    await tester.pumpWidget(
      _wrap(const CreatorToolsScreen()),
    );
    await tester.pump();
    expect(find.text('Инструменты автора'), findsOneWidget);
  });

  testWidgets('PromotedPostsScreen mounts', (tester) async {
    await tester.pumpWidget(
      _wrap(const PromotedPostsScreen()),
    );
    await tester.pump();
    expect(find.text('Продвижение'), findsOneWidget);
  });

  testWidgets('ScheduledPostsScreen mounts', (tester) async {
    await tester.pumpWidget(
      _wrap(const ScheduledPostsScreen()),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('AdminRefundQueueScreen mounts', (tester) async {
    await tester.pumpWidget(
      _wrap(const AdminRefundQueueScreen()),
    );
    await tester.pump();
    expect(find.text('Возвраты'), findsOneWidget);
  });
}
