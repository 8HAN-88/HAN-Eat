import 'package:flutter/material.dart';

import '../../../services/flex_subscription_service.dart';
import '../../../services/subscription_status_cache.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import 'flex_gift_sheet.dart';
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
  bool _fromCache = false;
  bool _busy = false;
  int? _hoverLevel;
  FlexFeature? _dragging;
  String _plan = 'monthly';

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
      await SubscriptionStatusCache.refreshFromServer();
      if (!mounted) return;
      setState(() {
        _me = me;
        _plan = me.plan;
        _fromCache = false;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      final cached = await FlexMeCache.load();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _me = cached;
          _plan = cached.plan;
          _fromCache = true;
          _error = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = userVisibleError(e);
        _loading = false;
      });
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _requireOnline() {
    if (!_fromCache) return true;
    _toast('Нужна сеть для оплаты подписки');
    return false;
  }

  Future<void> _changeLevel(int level) async {
    final me = _me;
    if (me == null || _busy || _dragging != null) return;
    if (!_requireOnline()) return;
    setState(() => _busy = true);
    try {
      final preview = await FlexSubscriptionApi.preview(level, plan: _plan);
      if (!mounted) return;
      final ok = await showFlexPreviewSheet(
        context,
        preview: preview,
        confirmDowngrade: preview.needsConfirm,
      );
      if (ok != true || !mounted) return;
      final result = await FlexSubscriptionApi.checkout(level, plan: _plan);
      if (!mounted) return;
      if (result.scheduled) {
        final pendingPlan = result.pendingPlan ?? _plan;
        final period = pendingPlan == 'yearly' ? 'год' : 'месяц';
        _toast(
          'С следующего периода будет уровень ${result.pendingLevel ?? level} · $period',
        );
        await _load();
      } else if (result.unchanged) {
        await _load();
      }
    } catch (e) {
      _toast(userVisibleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drop(FlexFeature feature, int level) async {
    if (!_requireOnline()) {
      setState(() {
        _dragging = null;
        _hoverLevel = null;
      });
      return;
    }
    if (feature.assignedLevel == level) {
      setState(() {
        _dragging = null;
        _hoverLevel = null;
      });
      return;
    }
    if (!feature.canPlace(level)) {
      _toast(feature.placementHint);
      setState(() {
        _dragging = null;
        _hoverLevel = null;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final next = await FlexSubscriptionApi.move(
        featureId: feature.id,
        targetLevel: level,
      );
      if (!mounted) return;
      setState(() => _me = next);
    } catch (e) {
      _toast(userVisibleError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dragging = null;
          _hoverLevel = null;
        });
      }
    }
  }

  Color _zoneColor(int level) {
    final dragging = _dragging;
    final scheme = Theme.of(context).colorScheme;
    if (dragging == null || _hoverLevel != level) {
      return scheme.surfaceContainerHighest;
    }
    return dragging.canPlace(level)
        ? const Color(0xFF2E7D32).withValues(alpha: 0.22)
        : const Color(0xFFC62828).withValues(alpha: 0.22);
  }

  List<Widget> _ladder(FlexMe me) {
    final children = <Widget>[
      if (_fromCache) ...[
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: const ListTile(
            leading: Icon(Icons.wifi_off_outlined),
            title: Text('Показаны сохранённые данные'),
            subtitle: Text('Нет связи с сервером. Потяните вниз, чтобы обновить.'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      _HeroCard(me: me),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'monthly', label: Text('Месяц')),
          ButtonSegment(value: 'yearly', label: Text('Год −2 мес.')),
        ],
        selected: {_plan},
        onSelectionChanged: (next) {
          if (_busy) return;
          setState(() => _plan = next.first);
        },
      ),
      const SizedBox(height: 12),
      if (me.presets.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in me.presets)
              ActionChip(
                label: Text('${preset.title} · ${preset.level}'),
                onPressed: _busy || _fromCache
                    ? null
                    : () => _changeLevel(preset.level),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      Text(
        'Нажмите уровень, чтобы сменить тариф. Удерживайте функцию, чтобы переставить её внутри блока.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      const SizedBox(height: 16),
    ];

    final covered = <int>{};
    final blocks = me.blocks.isNotEmpty
        ? me.blocks
        : const [
            FlexBlock(key: 'A', title: 'Базовые функции', minLevel: 1, maxLevel: 3),
            FlexBlock(key: 'B', title: 'Расширенные функции', minLevel: 4, maxLevel: 6),
            FlexBlock(key: 'C', title: 'PRO', minLevel: 7, maxLevel: 10),
            FlexBlock(key: 'D', title: 'Мессенджер+', minLevel: 11, maxLevel: 16),
            FlexBlock(key: 'E', title: 'Ещё', minLevel: 17, maxLevel: 20),
            FlexBlock(key: 'F', title: 'Медиа+', minLevel: 21, maxLevel: 24),
            FlexBlock(key: 'G', title: 'Чат+', minLevel: 25, maxLevel: 28),
            FlexBlock(key: 'H', title: 'Telegram+', minLevel: 29, maxLevel: 32),
            FlexBlock(key: 'I', title: 'Премиум', minLevel: 33, maxLevel: 36),
            FlexBlock(key: 'J', title: 'Ещё+', minLevel: 37, maxLevel: 40),
            FlexBlock(key: 'K', title: 'Сторис+', minLevel: 41, maxLevel: 44),
            FlexBlock(key: 'L', title: 'Входящие+', minLevel: 45, maxLevel: 48),
            FlexBlock(key: 'M', title: 'Контроль', minLevel: 49, maxLevel: 52),
            FlexBlock(key: 'N', title: 'Premium+', minLevel: 53, maxLevel: 56),
            FlexBlock(key: 'O', title: 'Ещё Premium', minLevel: 57, maxLevel: 60),
            FlexBlock(key: 'P', title: 'Бизнес', minLevel: 61, maxLevel: 64),
            FlexBlock(key: 'Q', title: 'Ещё бизнес', minLevel: 65, maxLevel: 68),
            FlexBlock(key: 'R', title: 'Магазин', minLevel: 69, maxLevel: 72),
          ];

    for (final block in blocks) {
      children.add(_BlockHeader(block: block));
      children.add(const SizedBox(height: 8));
      for (var level = block.minLevel; level <= block.maxLevel; level++) {
        covered.add(level);
        children.add(_buildRung(me, level));
      }
      children.add(const SizedBox(height: 8));
    }

    for (var level = 1; level <= me.maxLevel; level++) {
      if (covered.contains(level)) continue;
      children.add(_buildRung(me, level));
    }

    if (me.nextFeature != null) {
      children.add(const SizedBox(height: 8));
      children.add(
        _NextCta(
          feature: me.nextFeature!,
          price: me.priceForPlan(me.nextLevel ?? (me.currentLevel + 1), _plan),
          yearly: _plan == 'yearly',
          onOpen: _busy || _fromCache
              ? null
              : () => _changeLevel(me.nextLevel ?? (me.currentLevel + 1)),
        ),
      );
    }
    return children;
  }

  Widget _buildRung(FlexMe me, int level) {
    final feature = me.featureAt(level);
    final current = me.active && me.currentLevel == level;
    final pending = me.pendingLevel == level;
    final dragging = _dragging;
    final hover = _hoverLevel == level;
    final invalidHover = dragging != null && hover && !dragging.canPlace(level);
    return DragTarget<FlexFeature>(
      onWillAcceptWithDetails: (details) {
        if (_fromCache) return false;
        setState(() {
          _hoverLevel = level;
          _dragging = details.data;
        });
        return true;
      },
      onLeave: (_) {
        if (_hoverLevel == level) {
          setState(() => _hoverLevel = null);
        }
      },
      onAcceptWithDetails: (details) => _drop(details.data, level),
      builder: (context, candidate, rejected) {
        final scheme = Theme.of(context).colorScheme;
        final borderColor = current
            ? scheme.primary
            : candidate.isNotEmpty
                ? (candidate.first?.canPlace(level) == true
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828))
                : scheme.outlineVariant;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _zoneColor(level),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: current ? 2 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _busy || _fromCache ? null : () => _changeLevel(level),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LevelBadge(
                          level: level,
                          current: current,
                          unlocked: me.active && me.currentLevel >= level,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${me.priceForPlan(level, _plan)} ₽ / ${me.periodLabel(_plan)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (current)
                          Text(
                            'Текущий',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (pending)
                          Text(
                            'С периода',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else if (me.active && me.currentLevel >= level)
                          Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20)
                        else
                          Icon(Icons.lock_outline_rounded, color: scheme.outline, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (feature == null)
                      Text(
                        'Свободный слот',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    else
                      _DraggableFeature(
                        feature: feature,
                        enabled: !_fromCache,
                      ),
                    if (invalidHover && dragging != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dragging.placementHint,
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя подписка'),
        actions: [
          IconButton(
            tooltip: 'Подарить',
            onPressed: me == null || _busy || _fromCache
                ? null
                : () => showFlexGiftSheet(context, me: me, plan: _plan),
            icon: const Icon(Icons.card_giftcard_outlined),
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
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: _ladder(me!),
                    ),
                  ),
      ),
    );
  }
}

class _BlockHeader extends StatelessWidget {
  const _BlockHeader({required this.block});
  final FlexBlock block;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Блок ${block.key} · ${block.title} (${block.minLevel}–${block.maxLevel})',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({
    required this.level,
    required this.current,
    required this.unlocked,
  });

  final int level;
  final bool current;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = current
        ? scheme.primary
        : unlocked
            ? scheme.primaryContainer
            : scheme.surfaceContainerHigh;
    final fg = current
        ? scheme.onPrimary
        : unlocked
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$level',
        style: TextStyle(color: fg, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DraggableFeature extends StatelessWidget {
  const _DraggableFeature({required this.feature, this.enabled = true});
  final FlexFeature feature;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final locked = feature.isFixed;
    final tile = ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(locked ? Icons.lock_rounded : Icons.drag_indicator_rounded),
      title: Text(feature.title),
      subtitle: Text(
        locked
            ? 'Закреплена на уровне ${feature.assignedLevel}'
            : 'Можно на ${feature.minLevel}–${feature.maxLevel}',
      ),
    );
    if (locked || !enabled) return tile;
    return LongPressDraggable<FlexFeature>(
      data: feature,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 280, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
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
    final price = me.currentLevel < 1
        ? me.basePriceRub
        : (me.isYearly ? me.priceForPlan(level) : me.priceRub);
    final currentFeature = me.featureAt(me.currentLevel);
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
            me.active
                ? me.isYearly
                    ? '$price ₽ / год · 2 месяца в подарок'
                    : '$price ₽ / месяц'
                : 'Соберите набор от ${me.basePriceRub} ₽ / месяц',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (currentFeature != null && me.active) ...[
            const SizedBox(height: 4),
            Text(
              currentFeature.title,
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
            ),
          ],
          if (me.active && me.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text(
              me.autoRenew
                  ? 'Продлится автоматически до ${_shortDate(me.expiresAt!)}'
                  : 'Действует до ${_shortDate(me.expiresAt!)}',
              style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
            ),
          ],
          if (me.pendingLevel != null || me.pendingPlan != null) ...[
            const SizedBox(height: 6),
            Text(
              'Со следующего периода — уровень ${me.pendingLevel ?? me.currentLevel}'
              '${me.pendingPlan == 'yearly' ? ' · год' : me.pendingPlan == 'monthly' ? ' · месяц' : ''}',
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
    this.yearly = false,
  });

  final FlexFeature feature;
  final int price;
  final VoidCallback? onOpen;
  final bool yearly;

  @override
  Widget build(BuildContext context) {
    final step = yearly ? 100 : 10;
    final unit = yearly ? 'год' : 'мес';
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
              'Открой всего за +$step ₽/$unit. Итого $price ₽.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onOpen,
              child: Text('Открыть за +$step ₽'),
            ),
          ],
        ),
      ),
    );
  }
}
