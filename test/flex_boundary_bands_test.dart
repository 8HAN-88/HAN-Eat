import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/subscription/application/flex_boundary_bands.dart';
import 'package:han_eat/services/flex_subscription_service.dart';

void main() {
  test('keeps drag boundaries from subscription blocks', () {
    const blocks = [
      FlexBlock(key: 'A', title: 'Базовые', minLevel: 1, maxLevel: 3),
      FlexBlock(key: 'C', title: 'PRO', minLevel: 7, maxLevel: 10),
      FlexBlock(key: 'B', title: 'Расширенные', minLevel: 4, maxLevel: 6),
    ];
    final bands = flexBoundaryBands(blocks: blocks, maxLevel: 10);
    expect(bands.map((b) => b.title).toList(), [
      'Базовые',
      'Расширенные',
      'PRO',
    ]);
    expect(bands[0].containsLevel(3), isTrue);
    expect(bands[0].containsLevel(4), isFalse);
    expect(bands[2].minLevel, 7);
    expect(bands[2].maxLevel, 10);
  });

  test('one band when catalog has no blocks', () {
    final bands = flexBoundaryBands(blocks: const [], maxLevel: 8);
    expect(bands, hasLength(1));
    expect(bands.single.minLevel, 1);
    expect(bands.single.maxLevel, 8);
  });
}
