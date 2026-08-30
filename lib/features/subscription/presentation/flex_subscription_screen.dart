import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../support/presentation/widgets/subscription_cancel_survey_sheet.dart';
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

class _FlexSubscriptionScreenState extends State<FlexSubscriptionScreen>
    with WidgetsBindingObserver {
  FlexMe? _me;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _awaitingCheckoutReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingCheckoutReturn) {
      _awaitingCheckoutReturn = false;
      _load();
    }
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
      _awaitingCheckoutReturn = true;
      if (mounted) await _load();
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        _StatusLine(me: me!),
                        const SizedBox(height: 10),
                        for (var level = 1; level <= me.maxLevel; level++)
                          _LevelCard(
                            level: level,
                            last: level == me.maxLevel,
                            price: FlexPurchaseLadder.priceRub(level),
                            features: flexFeaturesAtLevel(me.levels, level),
                            current: me.active && me.currentLevel == level,
                            highlight: widget.initialLevel == level,
                            busy: _busy,
                            onBuy: () => _buyLevel(level),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () =>
                              context.push(FlexConstructorRoute.path),
                          child: const Text('Переставить возможности'),
                        ),
                        if (me.active) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final ok =
                                        await runSubscriptionCancelFlow(
                                      context,
                                    );
                                    if (ok && mounted) await _load();
                                  },
                            child: const Text('Отменить подписку'),
                          ),
                        ],
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
        : 'Одна подписка · ${me.maxLevel} ступеней · от ${FlexPurchaseLadder.basePriceRub} ₽';
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.level,
    required this.last,
    required this.price,
    required this.features,
    required this.current,
    required this.highlight,
    required this.busy,
    required this.onBuy,
  });

  final int level;
  final bool last;
  final int price;
  final List<FlexFeature> features;
  final bool current;
  final bool highlight;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = features.isEmpty
        ? 'Свободный слот'
        : features.map((f) => f.title).join(' · ');
    final description = features
        .map((f) => f.description?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .join(' ');
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 8),
      child: Card(
        margin: EdgeInsets.zero,
        color: current
            ? scheme.primaryContainer
            : highlight
                ? scheme.secondaryContainer.withValues(alpha: 0.7)
                : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: current || busy ? null : onBuy,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: current
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: current
                          ? scheme.onPrimary
                          : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '$price ₽/мес',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (current)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Ваш',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
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
      ),
    );
  }
}
