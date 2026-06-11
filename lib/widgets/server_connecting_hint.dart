import 'package:flutter/material.dart';

/// Подсказка при долгом запросе к API (вход, регистрация).
class ServerConnectingHint extends StatelessWidget {
  const ServerConnectingHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Подключаемся к серверу…\nЭто может занять до минуты при слабом интернете.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }
}
