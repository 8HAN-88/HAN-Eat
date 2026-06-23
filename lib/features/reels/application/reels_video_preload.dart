import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../services/video_cache_service.dart';

/// Предзагрузка контроллеров рилсов: сначала текущий, соседи — с задержкой.
Future<void> initializeReelVideosStaggered({
  required List<int> indices,
  required int priorityIndex,
  required Future<void> Function(int index) initSingle,
  Duration neighborDelay = const Duration(milliseconds: 400),
}) async {
  if (indices.isEmpty) return;
  final pending = indices.toSet();

  if (pending.remove(priorityIndex)) {
    await initSingle(priorityIndex);
  }

  Future<void> initNeighbor(int i) async {
    if (!pending.remove(i)) return;
    await initSingle(i);
  }

  final next = priorityIndex + 1;
  if (pending.contains(next)) {
    unawaited(
      Future<void>.delayed(neighborDelay, () => initNeighbor(next)),
    );
  }

  final prev = priorityIndex - 1;
  if (pending.contains(prev)) {
    unawaited(
      Future<void>.delayed(
        neighborDelay + const Duration(milliseconds: 140),
        () => initNeighbor(prev),
      ),
    );
  }

  for (final i in pending.toList()) {
    if ((i - priorityIndex).abs() > 1) continue;
    final delay = neighborDelay +
        Duration(milliseconds: 180 * (i - priorityIndex).abs());
    unawaited(Future<void>.delayed(delay, () => initNeighbor(i)));
  }
}

void prefetchReelVideoUrls(Iterable<String?> urls) {
  if (kIsWeb) return;
  for (final url in urls) {
    if (url != null && url.isNotEmpty) {
      VideoCacheService.prefetchInBackground(url);
    }
  }
}
