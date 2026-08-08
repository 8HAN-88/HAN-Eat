import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/chat_search_date.dart';

void main() {
  group('messageMatchesSearchDate', () {
    test('null day matches anything', () {
      expect(
        messageMatchesSearchDate(DateTime(2026, 8, 8, 12), null),
        isTrue,
      );
    });

    test('matches same local calendar day', () {
      expect(
        messageMatchesSearchDate(
          DateTime(2026, 8, 8, 23, 59),
          DateTime(2026, 8, 8),
        ),
        isTrue,
      );
      expect(
        messageMatchesSearchDate(
          DateTime(2026, 8, 9, 0, 1),
          DateTime(2026, 8, 8),
        ),
        isFalse,
      );
    });
  });

  group('searchDateQueryBounds', () {
    test('formats YYYY-MM-DD for same day', () {
      final bounds = searchDateQueryBounds(DateTime(2026, 8, 8, 15));
      expect(bounds.dateFrom, '2026-08-08');
      expect(bounds.dateTo, '2026-08-08');
    });
  });

  group('searchDateChipLabel', () {
    test('formats dd.MM.yyyy', () {
      expect(searchDateChipLabel(DateTime(2026, 8, 8)), '08.08.2026');
    });
  });
}
