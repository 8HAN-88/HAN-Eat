// Client-side bulk review of join requests (Telegram-like Approve/Decline all).

class JoinRequestsBulkResult {
  const JoinRequestsBulkResult({
    required this.succeeded,
    required this.failed,
  });

  final int succeeded;
  final int failed;

  int get total => succeeded + failed;
}

/// Runs [review] for each item sequentially; continues after individual failures.
Future<JoinRequestsBulkResult> reviewJoinRequestsBulk<T>({
  required List<T> items,
  required Future<void> Function(T item) review,
}) async {
  var succeeded = 0;
  var failed = 0;
  for (final item in items) {
    try {
      await review(item);
      succeeded++;
    } catch (_) {
      failed++;
    }
  }
  return JoinRequestsBulkResult(succeeded: succeeded, failed: failed);
}

String joinRequestsBulkSnackMessage({
  required bool approve,
  required JoinRequestsBulkResult result,
}) {
  if (result.total == 0) {
    return 'Нет заявок';
  }
  if (result.failed == 0) {
    return approve
        ? 'Принято: ${result.succeeded}'
        : 'Отклонено: ${result.succeeded}';
  }
  return approve
      ? 'Принято: ${result.succeeded}, ошибок: ${result.failed}'
      : 'Отклонено: ${result.succeeded}, ошибок: ${result.failed}';
}
