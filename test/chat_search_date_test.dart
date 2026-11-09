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
    test('covers the local calendar day in UTC', () {
      final bounds = searchDateQueryBounds(DateTime(2026, 8, 8, 15));
      final from = DateTime.parse(bounds.dateFrom).toLocal();
      final to = DateTime.parse(bounds.dateTo).toLocal();
      expect(from, DateTime(2026, 8, 8));
      expect(to.year, 2026);
      expect(to.month, 8);
      expect(to.day, 8);
      expect(to.hour, 23);
      expect(to.minute, 59);
      expect(to.second, 59);
    });
  });

  group('searchDateChipLabel', () {
    test('formats dd.MM.yyyy', () {
      expect(searchDateChipLabel(DateTime(2026, 8, 8)), '08.08.2026');
    });
  });
}
