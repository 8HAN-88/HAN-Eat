import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/subscription/application/flex_level_features.dart';
import 'package:han_eat/services/flex_subscription_service.dart';

FlexFeature _feature({
  required int id,
  required String title,
  required int level,
}) {
  return FlexFeature(
    id: id,
    slug: 's$id',
    title: title,
    assignedLevel: level,
    minLevel: 1,
    maxLevel: 10,
    featureType: 'movable',
    movable: true,
    required: false,
    unlocked: false,
  );
}

void main() {
  final catalog = [
    _feature(id: 1, title: 'Без рекламы', level: 1),
    _feature(id: 2, title: 'Значок', level: 1),
    _feature(id: 3, title: 'AI', level: 4),
  ];

  test('lists every feature parked on a level', () {
    final atOne = flexFeaturesAtLevel(catalog, 1);
    expect(atOne.map((f) => f.title).toList(), ['Без рекламы', 'Значок']);
    expect(flexFeaturesAtLevel(catalog, 2), isEmpty);
  });

  test('unlocks every feature up to the paid level', () {
    final unlocked = flexFeaturesUnlockedBy(catalog, 4);
    expect(unlocked.map((f) => f.slug).toList(), ['s1', 's2', 's3']);
  });
}
