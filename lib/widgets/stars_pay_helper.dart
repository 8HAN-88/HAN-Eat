import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/app_router.dart';
import '../services/paid_features_service.dart';
import '../utils/api_error_parser.dart' show ApiClientException, userVisibleError;

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
  if (error is ApiClientException) {
    if (error.code == 'STARS_REQUIRED') return true;
    if (error.statusCode == 402) return true;
  }
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
  final stars = isStarsRequiredError(error);
  final message = userVisibleError(
    error,
    fallback: fallback ?? (stars ? 'Недостаточно звёзд' : 'Произошла ошибка'),
  );
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: stars
          ? SnackBarAction(
              label: 'Купить ★',
              onPressed: () {
                if (context.mounted) {
                  context.push(StarsWalletRoute.path);
                }
              },
            )
          : null,
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class StarsTipDraft {
  const StarsTipDraft({
    required this.amount,
    this.message,
  });

  final int amount;
  final String? message;
}

/// Telegram-like Stars tip amount + optional note (presets + custom).
Future<StarsTipDraft?> pickStarsTipDraft(
  BuildContext context, {
  String title = 'Отправить звёзды',
  String? subtitle,
}) async {
  const presets = <int>[1, 5, 10, 50, 100, 250];
  final amountController = TextEditingController(text: '50');
  final messageController = TextEditingController();
  var selectedPreset = 50;
  final result = await showDialog<StarsTipDraft>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              Text(
                subtitle.trim(),
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in presets)
                  ChoiceChip(
                    label: Text('$n ★'),
                    selected: selectedPreset == n,
                    onSelected: (_) {
                      setLocal(() {
                        selectedPreset = n;
                        amountController.text = '$n';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Количество звёзд',
                hintText: 'например, 50',
              ),
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                setLocal(() {
                  selectedPreset = (n != null && presets.contains(n)) ? n : -1;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Сообщение (опционально)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final amount = int.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0) return;
              final note = messageController.text.trim();
              Navigator.pop(
                ctx,
                StarsTipDraft(
                  amount: amount,
                  message: note.isEmpty ? null : note,
                ),
              );
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    ),
  );
  amountController.dispose();
  messageController.dispose();
  return result;
}

/// Telegram-like paid reaction amount picker (1 / 5 / 10 / 50 / 100 ★).
Future<int?> pickPaidReactionStars(BuildContext context) async {
  const presets = <int>[1, 5, 10, 50, 100];
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
                'Платная реакция',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Выберите, сколько звёзд отправить автору сообщения.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in presets)
                    ActionChip(
                      avatar: const Icon(Icons.star_rounded, size: 18),
                      label: Text('$n ★'),
                      onPressed: () => Navigator.pop(ctx, n),
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

class ChannelSubscribeChoice {
  const ChannelSubscribeChoice({
    required this.months,
    required this.autoRenew,
  });

  final int months;
  final bool autoRenew;
}

/// Telegram-like channel Stars subscribe sheet (months + auto-renew).
Future<ChannelSubscribeChoice?> showChannelSubscribeSheet(
  BuildContext context, {
  required String channelName,
  required int monthlyPriceStars,
}) async {
  var months = 1;
  var autoRenew = true;
  return showModalBottomSheet<ChannelSubscribeChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final total = monthlyPriceStars * months;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Подписка на канал',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '«$channelName» · $monthlyPriceStars ★/мес',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Срок',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in const [1, 3, 6, 12])
                        ChoiceChip(
                          selected: months == m,
                          label: Text(m == 1 ? '1 мес' : '$m мес'),
                          onSelected: (_) => setLocal(() => months = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Автопродление'),
                    subtitle: const Text(
                      'Как в Telegram: списывать звёзды каждый месяц',
                    ),
                    value: autoRenew,
                    onChanged: (v) => setLocal(() => autoRenew = v),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$total ★',
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
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(
                            ctx,
                            ChannelSubscribeChoice(
                              months: months,
                              autoRenew: autoRenew,
                            ),
                          ),
                          child: const Text('Подписаться'),
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
    },
  );
}

/// Manage active channel Stars subscription (auto-renew / cancel / extend).
Future<bool> showChannelManageSubscriptionSheet(
  BuildContext context, {
  required int channelId,
  required String channelName,
  required int monthlyPriceStars,
}) async {
  ChannelSubscriptionInfo? info;
  Object? loadError;
  var busy = false;
  var changed = false;

  Future<void> reload(void Function(void Function()) setLocal) async {
    try {
      final next = await PaidFeaturesService.getChannelSubscription(channelId);
      setLocal(() {
        info = next;
        loadError = null;
      });
    } catch (e) {
      setLocal(() => loadError = e);
    }
  }

  Future<void> applyAutoRenew(
    BuildContext ctx,
    void Function(void Function()) setLocal,
    bool autoRenew,
  ) async {
    setLocal(() => busy = true);
    try {
      final next = await PaidFeaturesService.updateChannelSubscription(
        channelId,
        autoRenew: autoRenew,
      );
      changed = true;
      setLocal(() {
        info = next;
        busy = false;
      });
    } catch (e) {
      setLocal(() => busy = false);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => applyAutoRenew(ctx, setLocal, autoRenew),
          ),
        ),
      );
    }
  }

  Future<void> applyCancel(
    BuildContext ctx,
    void Function(void Function()) setLocal,
  ) async {
    setLocal(() => busy = true);
    try {
      final next =
          await PaidFeaturesService.cancelChannelSubscription(channelId);
      changed = true;
      setLocal(() {
        info = next;
        busy = false;
      });
    } catch (e) {
      setLocal(() => busy = false);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => applyCancel(ctx, setLocal),
          ),
        ),
      );
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          if (info == null && loadError == null) {
            reload(setLocal);
          }
          final scheme = Theme.of(ctx).colorScheme;
          final sub = info;
          final expires = sub?.expiresAt;
          final expiresLabel = expires == null
              ? '—'
              : DateFormat('d MMM yyyy, HH:mm', 'ru').format(expires.toLocal());

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Управление подпиской',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '«$channelName»',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (loadError != null) ...[
                    Text(userVisibleError(loadError!)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => reload(setLocal),
                      child: const Text('Повторить'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).maybePop(),
                      child: const Text('Закрыть'),
                    ),
                  ]
                  else if (sub == null)
                    Column(
                      children: [
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    )
                  else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        sub.isActive
                            ? Icons.check_circle_rounded
                            : Icons.schedule_rounded,
                        color: sub.isActive
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        sub.isActive ? 'Активна до $expiresLabel' : 'Не активна',
                      ),
                      subtitle: Text(
                        sub.autoRenew
                            ? 'Автопродление включено · $monthlyPriceStars ★/мес'
                            : 'Автопродление выключено',
                      ),
                    ),
                    if (sub.isActive) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Автопродление'),
                        value: sub.autoRenew,
                        onChanged: busy
                            ? null
                            : (v) => applyAutoRenew(ctx, setLocal, v),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: busy
                              ? null
                              : () async {
                                  final choice =
                                      await showChannelSubscribeSheet(
                                    ctx,
                                    channelName: channelName,
                                    monthlyPriceStars: monthlyPriceStars,
                                  );
                                  if (choice == null || !ctx.mounted) return;
                                  setLocal(() => busy = true);
                                  try {
                                    await PaidFeaturesService.subscribeChannel(
                                      channelId,
                                      months: choice.months,
                                      autoRenew: choice.autoRenew,
                                    );
                                    changed = true;
                                    await reload(setLocal);
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      await showStarsRequiredSnack(ctx, e);
                                    }
                                  } finally {
                                    if (ctx.mounted) {
                                      setLocal(() => busy = false);
                                    }
                                  }
                                },
                          child: const Text('Продлить'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: busy || !sub.autoRenew
                              ? null
                              : () async {
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('Отменить автопродление?'),
                                      content: Text(
                                        'Доступ сохранится до $expiresLabel. '
                                        'После этой даты подписка не продлится.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dCtx, false),
                                          child: const Text('Назад'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(dCtx, true),
                                          child: const Text('Отменить'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true || !ctx.mounted) return;
                                  await applyCancel(ctx, setLocal);
                                },
                          child: const Text('Отменить автопродление'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
  return changed;
}
