import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';

/// Legacy Firestore moderation — перенаправление на Postgres API.
@Deprecated('Use ModerationQueueScreen via ModerationQueueRoute')
class ModeratorPage extends StatelessWidget {
  const ModeratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go(ModerationQueueRoute.path);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
