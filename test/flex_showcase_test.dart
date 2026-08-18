import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/flex_subscription_service.dart';

FlexFeature _feature({
  required int id,
  required String slug,
  required int level,
  int min = 1,
  int max = 10,
  String type = 'movable',
  bool movable = true,
}) {
  return FlexFeature(
    id: id,
    slug: slug,
    title: slug,
    assignedLevel: level,
    minLevel: min,
    maxLevel: max,
    featureType: type,
    movable: movable,
    required: false,
    unlocked: level <= 6,
  );
}

void main() {
  final me = FlexMe(
    currentLevel: 6,
    priceRub: 89,
    maxLevel: 10,
    active: true,
    basePriceRub: 39,
    stepPriceRub: 10,
    levels: [
      _feature(id: 1, slug: 'ad_free', level: 1, min: 1, max: 1, type: 'fixed', movable: false),
      _feature(id: 2, slug: 'exclusive_reactions', level: 2, min: 1, max: 3),
      _feature(id: 4, slug: 'ai_recommendations', level: 4, min: 4, max: 6),
    ],
    blocks: const [
      FlexBlock(key: 'A', title: 'Базовые функции', minLevel: 1, maxLevel: 3),
      FlexBlock(key: 'B', title: 'Расширенные функции', minLevel: 4, maxLevel: 6),
      FlexBlock(key: 'C', title: 'PRO', minLevel: 7, maxLevel: 10),
    ],
  );

  test('price follows 39 + (level-1)*10', () {
    expect(me.priceForLevel(1), 39);
    expect(me.priceForLevel(6), 89);
    expect(me.priceForLevel(10), 129);
    expect(me.priceForPlan(1, 'yearly'), 390);
    expect(me.priceForPlan(6, 'yearly'), 890);
    expect(me.periodLabel('yearly'), 'год');
  });

  test('presets parse from payload', () {
    final parsed = FlexMe.fromJson({
      'current_level': 3,
      'price_rub': 59,
      'max_level': 10,
      'active': true,
      'levels': const [],
      'blocks': const [],
      'presets': [
        {'key': 'basic', 'title': 'Базовый', 'level': 3},
        {'key': 'plus', 'title': 'Расширенный', 'level': 6},
      ],
    });
    expect(parsed.presets.map((p) => p.level).toList(), [3, 6]);
  });

  test('featureAt and blockFor resolve ladder slots', () {
    expect(me.featureAt(4)?.slug, 'ai_recommendations');
    expect(me.featureAt(5), isNull);
    expect(me.blockFor(2)?.key, 'A');
    expect(me.blockFor(5)?.key, 'B');
    expect(me.blockFor(9)?.key, 'C');
  });

  test('placement rule is short and block-aware', () {
    final reactions = me.featureAt(2)!;
    final ai = me.featureAt(4)!;
    final ads = me.featureAt(1)!;
    expect(reactions.canPlace(3), isTrue);
    expect(reactions.canPlace(5), isFalse);
    expect(reactions.placementRule, 'только 1–3');
    expect(ai.placementRule, 'только 4–6');
    expect(ai.placementHint, 'Можно поставить только на 4–6');
    expect(ads.isFixed, isTrue);
    expect(ads.canPlace(1), isFalse);
    expect(ads.placementHint, 'Закреплена на уровне 1');
  });
}
