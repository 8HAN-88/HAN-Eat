import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';

/// Legacy экран рецептов (локальный поиск). Основное приложение — [MainFeedScreen].
@Deprecated('Use MainFeedScreen / MenuScreen via GoRouter')
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go(FeedRoute.path);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
