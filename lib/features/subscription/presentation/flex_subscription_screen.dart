import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../application/flex_level_features.dart';
import '../application/flex_purchase_ladder.dart';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
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
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        _StatusLine(me: me!),
                        const SizedBox(height: 10),
                        Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var level = 1;
                                  level <= me.maxLevel;
                                  level++) ...[
                                if (level > 1) const Divider(height: 1),
                                _LevelRow(
                                  level: level,
                                  price: FlexPurchaseLadder.priceRub(level),
                                  features: flexFeaturesAtLevel(
                                    me.levels,
                                    level,
                                  ),
                                  current:
                                      me.active && me.currentLevel == level,
                                  highlight: widget.initialLevel == level,
                                  busy: _busy,
                                  onBuy: () => _buyLevel(level),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
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

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.me});
  final FlexMe me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = me.active
        ? 'Уровень ${me.currentLevel} · ${me.priceRub} ₽/мес'
        : 'Одна подписка · ${me.maxLevel} уровней · от ${FlexPurchaseLadder.basePriceRub} ₽';
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.price,
    required this.features,
    required this.current,
    required this.highlight,
    required this.busy,
    required this.onBuy,
  });

  final int level;
  final int price;
  final List<FlexFeature> features;
  final bool current;
  final bool highlight;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titles = features.isEmpty
        ? 'Свободный слот'
        : features.map((f) => f.title).join(' · ');
    return Material(
      color: current
          ? scheme.primaryContainer
          : highlight
              ? scheme.secondaryContainer.withValues(alpha: 0.65)
              : Colors.transparent,
      child: InkWell(
        onTap: current || busy ? null : onBuy,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$level',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$price ₽',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(
                  titles,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (current)
                Text(
                  'Ваш',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                )
              else
                TextButton(
                  onPressed: busy ? null : onBuy,
                  child: const Text('Оформить'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
