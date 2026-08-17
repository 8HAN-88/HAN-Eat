import 'package:flutter/material.dart';

import '../../../services/flex_subscription_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';

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
        SnackBar(content: Text(userVisibleError(e))),
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
        SnackBar(content: Text(userVisibleError(e))),
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
                ? Center(child: Text(_error!))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: me!.maxLevel,
                    itemBuilder: (context, index) {
                      final level = index + 1;
                      FlexFeature? feature;
                      for (final item in me.levels) {
                        if (item.assignedLevel == level) {
                          feature = item;
                          break;
                        }
                      }
                      final price = 39 + (level - 1) * 10;
                      return DragTarget<FlexFeature>(
                        onWillAcceptWithDetails: (details) {
                          setState(() {
                            _hoverLevel = level;
                            _dragging = details.data;
                          });
                          return details.data.canPlace(level) ||
                              details.data.assignedLevel == level;
                        },
                        onLeave: (_) {
                          if (_hoverLevel == level) {
                            setState(() => _hoverLevel = null);
                          }
                        },
                        onAcceptWithDetails: (details) => _drop(details.data, level),
                        builder: (context, candidate, rejected) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _zoneColor(level),
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
                                if (feature == null)
                                  const Text('Свободный слот')
                                else
                                  _DraggableFeature(feature: feature),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
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
