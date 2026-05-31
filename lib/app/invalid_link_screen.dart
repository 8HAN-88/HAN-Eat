import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_empty_state.dart';

/// Экран для битых deep link / неверных id в маршруте.
class InvalidLinkScreen extends StatelessWidget {
  const InvalidLinkScreen({
    super.key,
    this.title = 'Ссылка',
    this.message = 'Неверная или устаревшая ссылка',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppEmptyState(
        icon: Icons.link_off_rounded,
        title: message,
        subtitle: 'Проверьте адрес или вернитесь на главную',
        action: FilledButton(
          onPressed: () => context.go('/feed'),
          child: const Text('На главную'),
        ),
      ),
    );
  }
}

/// Парсит положительный int из path/query (для GoRouter).
int? parseRoutePositiveId(String? raw) {
  final id = int.tryParse(raw ?? '');
  if (id == null || id < 1) return null;
  return id;
}
