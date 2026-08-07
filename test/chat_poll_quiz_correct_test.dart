import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/models/chat_poll.dart';

void main() {
  group('resolveQuizCorrectIndices', () {
    test('maps controller index past empty slots', () {
      expect(
        resolveQuizCorrectIndices(
          rawOptionTexts: ['A', '', 'B', 'C'],
          correctControllerIndex: 2,
        ),
        [1],
      );
    });

    test('returns empty when correct option text is empty', () {
      expect(
        resolveQuizCorrectIndices(
          rawOptionTexts: ['A', '', 'C'],
          correctControllerIndex: 1,
        ),
        isEmpty,
      );
    });

    test('returns empty when quiz answer not selected', () {
      expect(
        resolveQuizCorrectIndices(
          rawOptionTexts: ['A', 'B'],
          correctControllerIndex: null,
        ),
        isEmpty,
      );
    });
  });
}
