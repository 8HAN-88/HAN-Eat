import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
/// Telegram-like received Star gifts: keep on profile or convert to ★.
class StarGiftsInventoryScreen extends StatefulWidget {
  const StarGiftsInventoryScreen({super.key});

  @override
  State<StarGiftsInventoryScreen> createState() =>
      _StarGiftsInventoryScreenState();
}

class _StarGiftsInventoryScreenState extends State<StarGiftsInventoryScreen> {
  bool _loading = true;
  String? _error;
  List<UserStarGift> _gifts = const [];
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gifts = await PaidFeaturesService.listMyGifts();
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  Future<void> _convert(UserStarGift gift) async {
    if (_busy.contains(gift.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Конвертировать подарок'),
        content: Text(
          '«${gift.title}» будет убран с профиля. Вы получите ${gift.stars} ★ на баланс.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Получить ${gift.stars} ★'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(gift.id));
    try {
      await PaidFeaturesService.convertGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts.where((g) => g.id != gift.id).toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+${gift.stars} ★ на балансе')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _keep(UserStarGift gift) async {
    if (_busy.contains(gift.id)) return;
    setState(() => _busy.add(gift.id));
    try {
      final next = await PaidFeaturesService.keepGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == next.id ? next : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  Future<void> _toggleDisplay(UserStarGift gift) async {
    if (_busy.contains(gift.id) || !gift.canConvert) return;
    setState(() => _busy.add(gift.id));
    try {
      final next = await PaidFeaturesService.setGiftDisplayed(
        gift.id,
        displayed: !gift.isDisplayed,
      );
      if (!mounted) return;
      setState(() {
        _gifts = _gifts
            .map((g) => g.id == next.id ? next : g)
            .toList(growable: false);
        _busy.remove(gift.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои подарки')),
      body: AppGradientBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }
    if (_gifts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          64,
          24,
          24 + floatingBottomPadding(context),
        ),
        children: const [
          Icon(Icons.card_giftcard_rounded, size: 48),
          SizedBox(height: 12),
          Text(
            'Пока нет подарков.\nКогда вам пришлют Stars Gift — он появится здесь.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        16 + floatingBottomPadding(context),
      ),
      itemCount: _gifts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final gift = _gifts[index];
        final busy = _busy.contains(gift.id);
        final scheme = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(gift.emoji, style: const TextStyle(fontSize: 36)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gift.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${gift.stars} ★ · ${gift.status == 'kept' ? 'В профиле' : 'Ожидает решения'}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (gift.isDisplayed)
                      Icon(Icons.visibility_rounded, color: scheme.primary)
                    else
                      Icon(
                        Icons.visibility_off_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                if (gift.note != null && gift.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    gift.note!.trim(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (gift.status == 'held')
                      FilledButton.tonal(
                        onPressed: busy ? null : () => unawaited(_keep(gift)),
                        child: const Text('Оставить'),
                      ),
                    FilledButton(
                      onPressed:
                          busy ? null : () => unawaited(_convert(gift)),
                      child: Text('В ★ · ${gift.stars}'),
                    ),
                    OutlinedButton(
                      onPressed:
                          busy ? null : () => unawaited(_toggleDisplay(gift)),
                      child: Text(
                        gift.isDisplayed ? 'Скрыть' : 'В профиль',
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
}
