class ManualRetryItem {
  const ManualRetryItem({
    required this.remainingSeconds,
    required this.isMedia,
  });

  final int? remainingSeconds;
  final bool isMedia;
}

int? remainingRetryDelay({
  required int? retryAfterSeconds,
  required DateTime? limitedAt,
  DateTime? now,
}) {
  if (retryAfterSeconds == null ||
      retryAfterSeconds <= 0 ||
      limitedAt == null) {
    return null;
  }
  final current = (now ?? DateTime.now()).toUtc();
  final elapsed = current.difference(limitedAt.toUtc()).inSeconds;
  final remaining = retryAfterSeconds - elapsed;
  return remaining <= 0 ? 0 : remaining;
}

int? nextManualRetryRemainingSeconds(Iterable<int?> values) {
  final list = values.whereType<int>().toList(growable: false);
  if (list.isEmpty) return null;
  list.sort();
  return list.first;
}

List<T> sortManualRetryItems<T>(
  List<T> items,
  int? Function(T item) remainingSecondsOf,
  bool Function(T item) isMediaOf,
) {
  final out = List<T>.from(items, growable: false);
  out.sort((a, b) {
    final aRetry = remainingSecondsOf(a) ?? 999999;
    final bRetry = remainingSecondsOf(b) ?? 999999;
    if (aRetry != bRetry) return aRetry.compareTo(bRetry);
    final aIsMedia = isMediaOf(a);
    final bIsMedia = isMediaOf(b);
    if (aIsMedia == bIsMedia) return 0;
    return aIsMedia ? 1 : -1;
  });
  return out;
}

List<T> readyManualRetryItems<T>(
  List<T> items,
  int? Function(T item) remainingSecondsOf,
) {
  return items
      .where((item) => (remainingSecondsOf(item) ?? 0) <= 0)
      .toList(growable: false);
}

int nextManualReadyRetryDeferrals({
  required bool isReschedule,
  required int currentDeferrals,
}) {
  if (!isReschedule) return 0;
  return (currentDeferrals + 1).clamp(0, 99);
}

bool shouldStopManualReadyRetry({
  required int deferrals,
  int maxDeferrals = 30,
}) {
  return deferrals >= maxDeferrals;
}

bool shouldTriggerScheduledReadyRetryNow({
  required bool hasSchedule,
  required int? nextRemainingSeconds,
  required bool sending,
  required bool bulkRetryBusy,
}) {
  return hasSchedule &&
      (nextRemainingSeconds ?? 0) <= 0 &&
      !sending &&
      !bulkRetryBusy;
}
