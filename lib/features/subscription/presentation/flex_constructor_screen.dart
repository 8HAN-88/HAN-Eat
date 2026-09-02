import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../application/flex_boundary_bands.dart';
import '../application/flex_level_features.dart';
import '../application/flex_purchase_ladder.dart';

class FlexConstructorScreen extends StatefulWidget {
  const FlexConstructorScreen({super.key});

  @override
  State<FlexConstructorScreen> createState() => _FlexConstructorScreenState();
}

class _FlexConstructorScreenState extends State<FlexConstructorScreen> {
  FlexMe? _me;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _hoverLevel;
  FlexFeature? _dragging;

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

  Color _zoneColor(int level) {
    final dragging = _dragging;
    if (dragging == null || _hoverLevel != level) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    return dragging.canPlace(level)
        ? const Color(0xFF2E7D32).withValues(alpha: 0.22)
        : const Color(0xFFC62828).withValues(alpha: 0.22);
  }

  Future<void> _drop(FlexFeature feature, int level) async {
    if (feature.assignedLevel == level) return;
    setState(() => _saving = true);
    try {
      final next = await FlexSubscriptionApi.move(
        featureId: feature.id,
        targetLevel: level,
      );
      if (!mounted) return;
      setState(() => _me = next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_drop(feature, level)),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _dragging = null;
          _hoverLevel = null;
        });
      }
    }
  }

  List<FlexFeature> _featuresAt(FlexMe me, int level) =>
      flexFeaturesAtLevel(me.levels, level);

  Future<void> _save() async {
    final me = _me;
    if (me == null) return;
    setState(() => _saving = true);
    try {
      final next = await FlexSubscriptionApi.saveLayout([
        for (final f in me.levels) FlexSlot(featureId: f.id, level: f.assignedLevel),
      ]);
      if (!mounted) return;
      setState(() => _me = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Конфигурация сохранена')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_save()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настроить подписку'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить'),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Text(
                        'Одна подписка. Возможности перетаскиваются только внутри своей границы.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      for (final band in flexBoundaryBands(
                        blocks: me!.blocks,
                        maxLevel: me.maxLevel,
                      )) ...[
                        _BoundaryHeader(band: band),
                        const SizedBox(height: 8),
                        for (var level = band.minLevel;
                            level <= band.maxLevel;
                            level++)
                          _LevelDropZone(
                            level: level,
                            features: _featuresAt(me, level),
                            color: _zoneColor(level),
                            onWillAccept: (feature) {
                              setState(() {
                                _hoverLevel = level;
                                _dragging = feature;
                              });
                              return feature.canPlace(level) ||
                                  feature.assignedLevel == level;
                            },
                            onLeave: () {
                              if (_hoverLevel == level) {
                                setState(() => _hoverLevel = null);
                              }
                            },
                            onAccept: (feature) => _drop(feature, level),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _BoundaryHeader extends StatelessWidget {
  const _BoundaryHeader({required this.band});
  final FlexBoundaryBand band;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${band.title} · уровни ${band.minLevel}–${band.maxLevel}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _LevelDropZone extends StatelessWidget {
  const _LevelDropZone({
    required this.level,
    required this.features,
    required this.color,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
  });

  final int level;
  final List<FlexFeature> features;
  final Color color;
  final bool Function(FlexFeature feature) onWillAccept;
  final VoidCallback onLeave;
  final ValueChanged<FlexFeature> onAccept;

  @override
  Widget build(BuildContext context) {
    final price = FlexPurchaseLadder.priceRub(level);
    return DragTarget<FlexFeature>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: candidate.isNotEmpty
                  ? (candidate.first?.canPlace(level) == true
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828))
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'УРОВЕНЬ $level — $price ₽',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (features.isEmpty)
                const Text('Свободный слот')
              else
                for (final feature in features)
                  _DraggableFeature(feature: feature),
            ],
          ),
        );
      },
    );
  }
}

class _DraggableFeature extends StatelessWidget {
  const _DraggableFeature({required this.feature});
  final FlexFeature feature;

  @override
  Widget build(BuildContext context) {
    final locked = !feature.movable || feature.featureType == 'fixed';
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(locked ? Icons.lock_rounded : Icons.drag_indicator_rounded),
      title: Text(feature.title),
      subtitle: Text(
        locked
            ? 'Закреплена на уровне ${feature.assignedLevel}'
            : 'Можно на ${feature.minLevel}–${feature.maxLevel}',
      ),
    );
    if (locked) return tile;
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
