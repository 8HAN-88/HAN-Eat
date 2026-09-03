import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../../services/auth_service.dart';
import '../../../services/paid_features_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/stars_pay_helper.dart';

/// Telegram-like unique gift resale board.
class StarGiftsMarketplaceScreen extends StatefulWidget {
  const StarGiftsMarketplaceScreen({super.key});

  @override
  State<StarGiftsMarketplaceScreen> createState() =>
      _StarGiftsMarketplaceScreenState();
}

class _StarGiftsMarketplaceScreenState extends State<StarGiftsMarketplaceScreen> {
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
      final gifts = await PaidFeaturesService.listMarketplaceGifts();
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

  Future<void> _buy(UserStarGift gift) async {
    final me = AuthService.instance.currentUser?.id;
    if (me != null && me == gift.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Это ваш подарок')),
      );
      return;
    }
    final price = gift.listedStars ?? 0;
    if (price <= 0 || _busy.contains(gift.id)) return;
    final ok = await confirmStarsSpend(
      context,
      title: 'Купить ${gift.title}',
      body: gift.serialLabel.isNotEmpty
          ? '${gift.emoji} ${gift.serialLabel} · продавец ${gift.sellerLabel}'
          : '${gift.emoji} · продавец ${gift.sellerLabel}',
      amountStars: price,
      confirmLabel: 'Купить',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(gift.id));
    try {
      await PaidFeaturesService.buyListedGift(gift.id);
      if (!mounted) return;
      setState(() {
        _gifts = _gifts.where((g) => g.id != gift.id).toList(growable: false);
        _busy.remove(gift.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${gift.emoji} ${gift.title} теперь ваш')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(gift.id));
      await showStarsRequiredSnack(
        context,
        e,
        onRetry: () => unawaited(_buy(gift)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Витрина подарков')),
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
        children: [
          const Icon(Icons.storefront_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Пока никто не выставил коллекционный подарок.\nВыставите свой из «Мои подарки».',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: () => context.push(StarGiftsInventoryRoute.path),
              icon: const Icon(Icons.card_giftcard_outlined),
              label: const Text('Мои подарки'),
            ),
          ),
        ],
      );
    }
    final me = AuthService.instance.currentUser?.id;
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
        final mine = me != null && me == gift.ownerId;
        final scheme = Theme.of(context).colorScheme;
        final price = gift.listedStars ?? 0;
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
                          if (gift.serialLabel.isNotEmpty)
                            Text(
                              gift.serialLabel,
                              style: TextStyle(
                                color: scheme.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (gift.sellerLabel.isNotEmpty)
                            Text(
                              'Продавец ${gift.sellerLabel}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '$price ★',
                      style: TextStyle(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: busy || mine ? null : () => unawaited(_buy(gift)),
                    child: Text(mine ? 'Ваш лот' : 'Купить · $price ★'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
