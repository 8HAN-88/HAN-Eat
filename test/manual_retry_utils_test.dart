import 'package:flutter_test/flutter_test.dart';
import 'package:han_eat/features/chat/presentation/manual_retry_utils.dart';

void main() {
  test('remainingRetryDelay returns null without required fields', () {
    expect(
      remainingRetryDelay(retryAfterSeconds: null, limitedAt: DateTime.now()),
      isNull,
    );
    expect(
      remainingRetryDelay(retryAfterSeconds: 10, limitedAt: null),
      isNull,
    );
  });

  test('remainingRetryDelay returns remaining seconds and floors at zero', () {
    final now = DateTime.utc(2026, 7, 5, 12, 0, 20);
    final limitedAt = DateTime.utc(2026, 7, 5, 12, 0, 10);
    expect(
      remainingRetryDelay(
        retryAfterSeconds: 30,
        limitedAt: limitedAt,
        now: now,
      ),
      20,
    );
    expect(
      remainingRetryDelay(
        retryAfterSeconds: 5,
        limitedAt: limitedAt,
        now: now,
      ),
      0,
    );
  });

  test('nextManualRetryRemainingSeconds returns smallest non-null value', () {
    expect(nextManualRetryRemainingSeconds([null, 12, 4, 9]), 4);
    expect(nextManualRetryRemainingSeconds([null, null]), isNull);
  });

  test('sortManualRetryItems sorts by remaining then text before media', () {
    final items = [
      const ManualRetryItem(remainingSeconds: 12, isMedia: true),
      const ManualRetryItem(remainingSeconds: 0, isMedia: true),
      const ManualRetryItem(remainingSeconds: 0, isMedia: false),
      const ManualRetryItem(remainingSeconds: null, isMedia: false),
    ];
    final sorted = sortManualRetryItems<ManualRetryItem>(
      items,
      (item) => item.remainingSeconds,
      (item) => item.isMedia,
    );
    expect(
      sorted.map((i) => (i.remainingSeconds, i.isMedia)).toList(),
      [(0, false), (0, true), (12, true), (null, false)],
    );
  });

  test('readyManualRetryItems keeps zero and null remaining items', () {
    final items = [
      const ManualRetryItem(remainingSeconds: 0, isMedia: false),
      const ManualRetryItem(remainingSeconds: null, isMedia: true),
      const ManualRetryItem(remainingSeconds: 3, isMedia: false),
    ];
    final ready = readyManualRetryItems<ManualRetryItem>(
        items, (i) => i.remainingSeconds);
    expect(ready.length, 2);
    expect(ready[0].remainingSeconds, 0);
    expect(ready[1].remainingSeconds, isNull);
  });

  test('nextManualReadyRetryDeferrals increments only for reschedule', () {
    expect(
      nextManualReadyRetryDeferrals(isReschedule: false, currentDeferrals: 7),
      0,
    );
    expect(
      nextManualReadyRetryDeferrals(isReschedule: true, currentDeferrals: 7),
      8,
    );
  });

  test('shouldStopManualReadyRetry uses max deferrals threshold', () {
    expect(shouldStopManualReadyRetry(deferrals: 29), isFalse);
    expect(shouldStopManualReadyRetry(deferrals: 30), isTrue);
    expect(
      shouldStopManualReadyRetry(deferrals: 5, maxDeferrals: 5),
      isTrue,
    );
  });

  test('shouldTriggerScheduledReadyRetryNow validates all preconditions', () {
    expect(
      shouldTriggerScheduledReadyRetryNow(
        hasSchedule: true,
        nextRemainingSeconds: 0,
        sending: false,
        bulkRetryBusy: false,
      ),
      isTrue,
    );
    expect(
      shouldTriggerScheduledReadyRetryNow(
        hasSchedule: false,
        nextRemainingSeconds: 0,
        sending: false,
        bulkRetryBusy: false,
      ),
      isFalse,
    );
    expect(
      shouldTriggerScheduledReadyRetryNow(
        hasSchedule: true,
        nextRemainingSeconds: 4,
        sending: false,
        bulkRetryBusy: false,
      ),
      isFalse,
    );
    expect(
      shouldTriggerScheduledReadyRetryNow(
        hasSchedule: true,
        nextRemainingSeconds: 0,
        sending: true,
        bulkRetryBusy: false,
      ),
      isFalse,
    );
  });
}
