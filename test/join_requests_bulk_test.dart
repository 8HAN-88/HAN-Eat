import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/application/join_requests_bulk.dart';

void main() {
  group('reviewJoinRequestsBulk', () {
    test('counts successes and continues after failures', () async {
      final result = await reviewJoinRequestsBulk<int>(
        items: [1, 2, 3, 4],
        review: (id) async {
          if (id.isEven) throw StateError('fail');
        },
      );
      expect(result.succeeded, 2);
      expect(result.failed, 2);
      expect(result.failedItems, [2, 4]);
      expect(result.total, 4);
    });

    test('empty list is a no-op', () async {
      final result = await reviewJoinRequestsBulk<int>(
        items: const [],
        review: (_) async {},
      );
      expect(result.succeeded, 0);
      expect(result.failed, 0);
    });
  });

  group('joinRequestsBulkSnackMessage', () {
    test('formats success and mixed outcomes', () {
      expect(
        joinRequestsBulkSnackMessage(
          approve: true,
          result: const JoinRequestsBulkResult(succeeded: 3, failed: 0),
        ),
        'Принято: 3',
      );
      expect(
        joinRequestsBulkSnackMessage(
          approve: false,
          result: const JoinRequestsBulkResult(succeeded: 2, failed: 1),
        ),
        'Отклонено: 2, ошибок: 1',
      );
      expect(
        joinRequestsBulkSnackMessage(
          approve: true,
          result: const JoinRequestsBulkResult(succeeded: 0, failed: 0),
        ),
        'Нет заявок',
      );
    });
  });
}
