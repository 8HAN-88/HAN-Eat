import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../services/video_cache_service.dart';

/// Предзагрузка контроллеров рилсов: приоритет текущему и соседям.
Future<void> initializeReelVideosStaggered({
  required List<int> indices,
  required int priorityIndex,
  required Future<void> Function(int index) initSingle,
}) async {
  if (indices.isEmpty) return;
  final pending = [...indices];

  if (pending.remove(priorityIndex)) {
    await initSingle(priorityIndex);
  }

  final next = priorityIndex + 1;
  if (pending.remove(next)) {
    unawaited(initSingle(next));
  }

  final prev = priorityIndex - 1;
  if (pending.remove(prev)) {
    unawaited(initSingle(prev));
  }

  for (final i in pending) {
    final delayMs = 250 * (i - priorityIndex).abs();
    unawaited(
      Future<void>.delayed(
        Duration(milliseconds: delayMs),
        () => initSingle(i),
      ),
    );
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
