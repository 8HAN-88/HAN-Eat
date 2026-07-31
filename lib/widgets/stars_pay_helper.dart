import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/app_router.dart';
import '../utils/api_error_parser.dart';

/// Shared Stars UX: confirm spend + recover from insufficient balance.
Future<bool> confirmStarsSpend(
  BuildContext context, {
  required String title,
  required String body,
  required int amountStars,
  String confirmLabel = 'Оплатить',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$amountStars ★',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.secondary,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}

bool isStarsRequiredError(Object error) {
  final raw = error.toString().toLowerCase();
  return raw.contains('stars_required') ||
      raw.contains('недостаточно звёзд') ||
      raw.contains('недостаточно звезд') ||
      raw.contains('402');
}

Future<void> showStarsRequiredSnack(
  BuildContext context,
  Object error, {
  String? fallback,
}) async {
  final message = userVisibleError(
    error,
    fallback: fallback ?? 'Недостаточно звёзд',
  );
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Купить ★',
        onPressed: () {
          if (context.mounted) {
            context.push(StarsWalletRoute.path);
          }
        },
      ),
    ),
  );
}

Future<int?> pickPaidMessageStars(
  BuildContext context, {
  required int current,
}) async {
  const presets = <int>[0, 1, 5, 10, 25, 50, 100];
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Плата за сообщения',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Как в Telegram: люди будут платить звёзды за каждое сообщение вам.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in presets)
                    ChoiceChip(
                      selected: n == current,
                      label: Text(n == 0 ? 'Выкл.' : '$n ★'),
                      onSelected: (_) => Navigator.pop(ctx, n),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
