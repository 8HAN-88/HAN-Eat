import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import 'flex_preview_sheet.dart';

class FlexSubscriptionScreen extends StatefulWidget {
  const FlexSubscriptionScreen({super.key});

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

  Future<void> _changeLevel(int level) async {
    final me = _me;
    if (me == null || _busy) return;
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
      final result = await FlexSubscriptionApi.checkout(level);
      if (!mounted) return;
      if (result.scheduled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'С следующего периода будет уровень ${result.pendingLevel ?? level}',
            ),
          ),
        );
        await _load();
      } else if (result.unchanged) {
        await _load();
      }
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
        title: const Text('Моя подписка'),
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
                        const SizedBox(height: 18),
                        Text(
                          'Доступно',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        for (final feature in me.levels)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              feature.unlocked
                                  ? Icons.check_circle_rounded
                                  : Icons.lock_outline_rounded,
                              color: feature.unlocked
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            title: Text(feature.title),
                            subtitle: Text(
                              feature.unlocked
                                  ? 'Уровень ${feature.assignedLevel}'
                                  : 'С уровня ${feature.assignedLevel}',
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (me.currentLevel > 1)
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeLevel(me.currentLevel - 1),
                                  child: Text(
                                    '← Уровень ${me.currentLevel - 1}',
                                  ),
                                ),
                              ),
                            if (me.currentLevel > 1 && me.nextLevel != null)
                              const SizedBox(width: 10),
                            if (me.nextLevel != null)
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeLevel(me.nextLevel!),
                                  child: Text(
                                    'Уровень ${me.nextLevel} →',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (me.nextFeature != null) ...[
                          const SizedBox(height: 16),
                          _NextCta(
                            feature: me.nextFeature!,
                            price: me.nextPriceRub ?? (me.priceRub + 10),
                            onOpen: _busy
                                ? null
                                : () => _changeLevel(me.nextLevel ?? (me.currentLevel + 1)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () => context.push(FlexConstructorRoute.path),
                          child: const Text('⚙️ Настроить подписку'),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

String _shortDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  return '$dd.$mm.${local.year}';
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.me});
  final FlexMe me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = me.currentLevel < 1 ? 1 : me.currentLevel;
    final price = me.currentLevel < 1 ? 39 : me.priceRub;
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
          Text('Моя подписка', style: TextStyle(color: scheme.onPrimaryContainer)),
          const SizedBox(height: 6),
          Text(
            'Уровень $level',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            me.active ? '$price ₽ / месяц' : 'Соберите набор от 39 ₽ / месяц',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (me.active && me.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              me.autoRenew
                  ? 'Продлится автоматически'
                  : 'Действует до ${_shortDate(me.expiresAt!)}',
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
            ),
          ],
          if (me.pendingLevel != null) ...[
            const SizedBox(height: 6),
            Text(
              'Со следующего периода — уровень ${me.pendingLevel}',
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextCta extends StatelessWidget {
  const _NextCta({
    required this.feature,
    required this.price,
    required this.onOpen,
  });

  final FlexFeature feature;
  final int price;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Следующая возможность', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('🔓 ${feature.title}'),
            const SizedBox(height: 4),
            Text(
              'Открой всего за +10 ₽/мес. Итого $price ₽.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onOpen,
              child: const Text('Открыть за +10 ₽'),
            ),
          ],
        ),
      ),
    );
  }
}
