import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/services/comment_service.dart';

void main() {
  group('readCommentsTotal', () {
    test('reads int, num string and defaults', () {
      expect(readCommentsTotal(4), 4);
      expect(readCommentsTotal(3.0), 3);
      expect(readCommentsTotal('7'), 7);
      expect(readCommentsTotal(null), 0);
      expect(readCommentsTotal('x'), 0);
    });
  });

  group('CommentsResponse.fromJson', () {
    test('parses total when API sends a string', () {
      final response = CommentsResponse.fromJson({
        'comments': [
          {
            'id': 1,
            'post_id': 28,
            'user_id': 2,
            'text': 'ок',
            'created_at': '2026-08-28T00:00:00.000Z',
          },
        ],
        'total': '12',
      });
      expect(response.total, 12);
      expect(response.comments, hasLength(1));
    });

    test('empty comments list still keeps server total', () {
      final response = CommentsResponse.fromJson({
        'comments': [],
        'total': 5,
      });
      expect(response.total, 5);
      expect(response.comments, isEmpty);
    });
  });
}
