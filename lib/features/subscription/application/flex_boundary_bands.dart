import '../../../services/flex_subscription_service.dart';

/// Видимая граница, внутри которой можно перетаскивать возможности.
class FlexBoundaryBand {
  const FlexBoundaryBand({
    required this.title,
    required this.minLevel,
    required this.maxLevel,
  });

  final String title;
  final int minLevel;
  final int maxLevel;

  bool containsLevel(int level) => level >= minLevel && level <= maxLevel;
}

List<FlexBoundaryBand> flexBoundaryBands({
  required List<FlexBlock> blocks,
  required int maxLevel,
}) {
  final cap = maxLevel < 1 ? 1 : maxLevel;
  if (blocks.isEmpty) {
    return [
      FlexBoundaryBand(title: 'Подписка', minLevel: 1, maxLevel: cap),
    ];
  }
  final bands = [
    for (final block in blocks)
      FlexBoundaryBand(
        title: block.title,
        minLevel: block.minLevel.clamp(1, cap),
        maxLevel: block.maxLevel.clamp(1, cap),
      ),
  ]..sort((a, b) => a.minLevel.compareTo(b.minLevel));
  return bands;
}
