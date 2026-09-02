import 'package:flutter/material.dart';

import '../../../../services/paid_features_service.dart';

class StarGiftSendDraft {
  const StarGiftSendDraft({
    required this.gift,
    this.message,
    this.hideName = false,
  });

  final StarGift gift;
  final String? message;
  final bool hideName;
}

Future<StarGift?> showStarGiftPickerSheet(BuildContext context) {
  return showModalBottomSheet<StarGift>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _StarGiftPickerSheet(),
  );
}

/// Picker + note / hide-my-name confirm (Telegram send-gift flow).
Future<StarGiftSendDraft?> showStarGiftSendFlow(BuildContext context) async {
  final gift = await showStarGiftPickerSheet(context);
  if (gift == null || !context.mounted) return null;
  final noteController = TextEditingController();
  var hideName = false;
  final confirmed = await showDialog<({String note, bool hideName})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('${gift.emoji} ${gift.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (gift.isLimited)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  gift.remaining != null
                      ? 'Лимитированный · осталось ${gift.remaining}'
                      : 'Лимитированный подарок',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            TextField(
              controller: noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Сообщение (опционально)',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Скрыть моё имя'),
              subtitle: Text(
                'На профиле получателя подарок будет без отправителя',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              value: hideName,
              onChanged: (v) => setLocal(() => hideName = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (note: noteController.text.trim(), hideName: hideName),
            ),
            child: Text('Отправить · ${gift.stars} ★'),
          ),
        ],
      ),
    ),
  );
  noteController.dispose();
  if (confirmed == null) return null;
  return StarGiftSendDraft(
    gift: gift,
    message: confirmed.note.isEmpty ? null : confirmed.note,
    hideName: confirmed.hideName,
  );
}

class _StarGiftPickerSheet extends StatefulWidget {
  const _StarGiftPickerSheet();

  @override
  State<_StarGiftPickerSheet> createState() => _StarGiftPickerSheetState();
}

class _StarGiftPickerSheetState extends State<_StarGiftPickerSheet> {
  late Future<List<StarGift>> _future;

  @override
  void initState() {
    super.initState();
    _future = PaidFeaturesService.getGifts();
  }

  void _reload() {
    setState(() {
      _future = PaidFeaturesService.getGifts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Подарки за звёзды',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Как в Telegram: выберите подарок — звёзды спишутся с кошелька',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<StarGift>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          'Не удалось загрузить каталог',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Повторить'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final gifts = snapshot.data!;
                if (gifts.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Text(
                          'Каталог пуст',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Повторить'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.92,
                  ),
                  itemBuilder: (context, index) {
                    final gift = gifts[index];
                    final soldOut = gift.isSoldOut;
                    return Opacity(
                      opacity: soldOut ? 0.45 : 1,
                      child: Material(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: soldOut
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Этот подарок распродан'),
                                    ),
                                  );
                                }
                              : () => Navigator.pop(context, gift),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  gift.emoji,
                                  style: const TextStyle(fontSize: 32),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  gift.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  soldOut
                                      ? 'Sold out'
                                      : gift.isLimited && gift.remaining != null
                                          ? '${gift.stars} ★ · ${gift.remaining}'
                                          : '${gift.stars} ★',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: scheme.secondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                if (gift.isLimited && !soldOut)
                                  Text(
                                    'limited',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
