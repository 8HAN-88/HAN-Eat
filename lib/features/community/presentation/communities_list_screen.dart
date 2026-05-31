import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';

/// Legacy Firestore «каналы» — перенаправление на Postgres-каналы.
@Deprecated('Use ChannelsMainScreen via ChannelsListRoute')
class CommunitiesListScreen extends StatelessWidget {
  const CommunitiesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go(ChannelsListRoute.path);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
