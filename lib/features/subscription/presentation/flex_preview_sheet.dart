import 'package:flutter/material.dart';

import '../../../services/flex_subscription_service.dart';

Future<bool?> showFlexPreviewSheet(
  BuildContext context, {
  required FlexPreview preview,
  bool confirmDowngrade = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                confirmDowngrade ? 'Понизить уровень?' : 'Твоя подписка',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text('Уровень ${preview.level} · ${preview.priceRub} ₽ / месяц'),
              const SizedBox(height: 12),
              Text(
                confirmDowngrade ? 'Станут недоступны' : 'Ты получишь',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (confirmDowngrade)
                for (final f in preview.disabled)
                  Text('⚠️ ${f.title}')
              else
                for (final f in preview.features)
                  Text('✅ ${f.title}'),
              if (!confirmDowngrade && preview.nextFeature != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Следующий уровень · ${preview.nextPriceRub} ₽ / месяц',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('➕ ${preview.nextFeature!.title}'),
              ],
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
                      child: Text(
                        confirmDowngrade
                            ? 'Понизить уровень'
                            : preview.deltaRub > 0
                                ? 'Оплатить ${preview.priceRub} ₽'
                                : 'Продолжить',
                      ),
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
}
