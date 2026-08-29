import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../application/flex_boundary_bands.dart';
import '../application/flex_level_features.dart';
import '../application/flex_purchase_ladder.dart';
import '../subscription_copy.dart';
import 'flex_preview_sheet.dart';

class FlexSubscriptionScreen extends StatefulWidget {
  const FlexSubscriptionScreen({super.key, this.initialLevel = 0});

  /// Подскролл к уровню, если открыли со старого тарифа.
  final int initialLevel;

  @override
  State<FlexSubscriptionScreen> createState() => _FlexSubscriptionScreenState();
}

class _FlexSubscriptionScreenState extends State<FlexSubscriptionScreen> {
  FlexMe? _me;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  final Map<int, GlobalKey> _levelKeys = {};

  GlobalKey _keyFor(int level) =>
      _levelKeys.putIfAbsent(level, GlobalKey.new);

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
      final me = await FlexSubscriptionApi.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
      _scrollToInitial();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
  }

  void _scrollToInitial() {
    final target = widget.initialLevel;
    if (target < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(target).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 320),
          alignment: 0.2,
        );
      }
    });
  }

  Future<void> _buyLevel(int level) async {
    final me = _me;
    if (me == null || _busy) return;
    if (me.active && me.currentLevel == level) return;
    setState(() => _busy = true);
    try {
      final preview = await FlexSubscriptionApi.preview(level);
      if (!mounted) return;
      final ok = await showFlexPreviewSheet(
        context,
        preview: preview,
        confirmDowngrade: preview.needsConfirm,
      );
      if (ok != true || !mounted) return;
      await FlexSubscriptionApi.checkout(level);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подписка'),
        actions: [
          IconButton(
            tooltip: 'Все возможности',
            onPressed: () => context.push(FlexShopRoute.path),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        _HeroCard(me: me!),
                        const SizedBox(height: 12),
                        Text(
                          'Одна подписка. Пакеты HanWe AI / Creator / Pro — те же возможности, что раньше. Ниже — все 10 уровней с полным списком функций.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Пакеты',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final product in const ['ai', 'creator', 'pro'])
                          _ClassicPackTile(
                            product: product,
                            level: FlexPurchaseLadder.levelForClassicProduct(
                              product,
                            ),
                            current: me.active &&
                                me.currentLevel ==
                                    FlexPurchaseLadder.levelForClassicProduct(
                                      product,
                                    ),
                            busy: _busy,
                            onBuy: () => _buyLevel(
                              FlexPurchaseLadder.levelForClassicProduct(
                                product,
                              ),
                            ),
                            onOpen: () {
                              final level =
                                  FlexPurchaseLadder.levelForClassicProduct(
                                product,
                              );
                              final ctx = _keyFor(level).currentContext;
                              if (ctx != null) {
                                Scrollable.ensureVisible(
                                  ctx,
                                  duration: const Duration(milliseconds: 280),
                                  alignment: 0.15,
                                );
                              }
                            },
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'Все уровни',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final band in flexBoundaryBands(
                          blocks: me.blocks,
                          maxLevel: me.maxLevel,
                        )) ...[
                          _BandTitle(band: band),
                          const SizedBox(height: 8),
                          for (var level = band.minLevel;
                              level <= band.maxLevel;
                              level++)
                            KeyedSubtree(
                              key: _keyFor(level),
                              child: _LevelBuyTile(
                                level: level,
                                price: FlexPurchaseLadder.priceRub(level),
                                atLevel: flexFeaturesAtLevel(me.levels, level),
                                unlocked: flexFeaturesUnlockedBy(me.levels, level),
                                current: me.active && me.currentLevel == level,
                                highlight: widget.initialLevel == level,
                                busy: _busy,
                                onBuy: () => _buyLevel(level),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () =>
                              context.push(FlexConstructorRoute.path),
                          child: const Text('Переставить возможности'),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.me});
  final FlexMe me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = me.currentLevel < 1 ? 1 : me.currentLevel;
    final price = me.currentLevel < 1
        ? FlexPurchaseLadder.basePriceRub
        : me.priceRub;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HanWe подписка',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            me.active ? 'Уровень $level' : 'Выберите уровень',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            me.active
                ? '$price ₽ / месяц'
                : 'От ${FlexPurchaseLadder.basePriceRub} ₽ / месяц',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ClassicPackTile extends StatelessWidget {
  const _ClassicPackTile({
    required this.product,
    required this.level,
    required this.current,
    required this.busy,
    required this.onBuy,
    required this.onOpen,
  });

  final String product;
  final int level;
  final bool current;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = FlexPurchaseLadder.priceRub(level);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(SubscriptionCopy.tierIcon(product)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      SubscriptionCopy.tierTitle(product),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '$price ₽/мес',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${SubscriptionCopy.tierSubtitle(product)} · уровень $level',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final line in SubscriptionCopy.tierBenefits(product))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $line'),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: current
                    ? Text('Ваш пакет', style: TextStyle(color: scheme.primary))
                    : FilledButton(
                        onPressed: busy ? null : onBuy,
                        child: const Text('Оформить'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandTitle extends StatelessWidget {
  const _BandTitle({required this.band});
  final FlexBoundaryBand band;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '${band.title} · ${band.minLevel}–${band.maxLevel}',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
    );
  }
}

class _LevelBuyTile extends StatelessWidget {
  const _LevelBuyTile({
    required this.level,
    required this.price,
    required this.atLevel,
    required this.unlocked,
    required this.current,
    required this.highlight,
    required this.busy,
    required this.onBuy,
  });

  final int level;
  final int price;
  final List<FlexFeature> atLevel;
  final List<FlexFeature> unlocked;
  final bool current;
  final bool highlight;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final previous = unlocked.length - atLevel.length;
    final pack = FlexPurchaseLadder.classicProductAtLevel(level);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: current
          ? scheme.primaryContainer
          : highlight
              ? scheme.secondaryContainer.withValues(alpha: 0.7)
              : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack == null
                        ? 'Уровень $level · $price ₽/мес'
                        : 'Уровень $level · ${SubscriptionCopy.tierTitle(pack)} · $price ₽/мес',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (current)
                  const Text('Ваш')
                else
                  FilledButton(
                    onPressed: busy ? null : onBuy,
                    child: const Text('Оформить'),
                  ),
              ],
            ),
            if (atLevel.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Свободный слот'),
              )
            else ...[
              const SizedBox(height: 8),
              Text(
                'На этом уровне',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              for (final feature in atLevel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${feature.title}'),
                      if ((feature.description ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 1),
                          child: Text(
                            feature.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            if (previous > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Включает все возможности уровней 1–${level - 1}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
