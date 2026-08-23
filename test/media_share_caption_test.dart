import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/utils/media_share_caption.dart';

void main() {
  group('normalizeMediaShareCaption', () {
    test('trims and drops empty', () {
      expect(normalizeMediaShareCaption(null), isNull);
      expect(normalizeMediaShareCaption(''), isNull);
      expect(normalizeMediaShareCaption('   '), isNull);
      expect(normalizeMediaShareCaption('  hello  '), 'hello');
    });

    test('previews custom emoji tokens', () {
      expect(
        normalizeMediaShareCaption('фото [[e:12]]'),
        isNot(contains('[[e:')),
      );
    });
  });
}
