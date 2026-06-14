import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/post_model.dart';
import 'product_analytics.dart';

class FeedAnalyticsService {
  FeedAnalyticsService._();

  static const Duration skipThreshold = Duration(milliseconds: 1200);
  static const Duration dwellThreshold = Duration(seconds: 3);

  static Future<void> impression(
    PostModel post, {
    required String feedSurface,
    int? position,
  }) {
    return _postEvent(
      'feed_impression',
      post,
      feedSurface: feedSurface,
      position: position,
    );
  }

  static Future<void> dwell(
    PostModel post, {
    required String feedSurface,
    required Duration duration,
    int? position,
  }) {
    return _postEvent(
      'feed_dwell',
      post,
      feedSurface: feedSurface,
      position: position,
      metadata: {
        'duration_seconds': _seconds(duration),
      },
    );
  }

  static Future<void> skip(
    PostModel post, {
    required String feedSurface,
    required Duration duration,
    int? position,
  }) {
    return _postEvent(
      'feed_skip',
      post,
      feedSurface: feedSurface,
      position: position,
      metadata: {
        'duration_seconds': _seconds(duration),
      },
    );
  }

  static Future<void> openDetail(
    PostModel post, {
    required String source,
    String? target,
  }) {
    return _postEvent(
      'feed_open_detail',
      post,
      feedSurface: source,
      metadata: {
        if (target != null) 'target': target,
      },
    );
  }

  static Future<void> reelProgress(
    PostModel post, {
    required Duration watched,
    Duration? duration,
    int? position,
  }) {
    final durationMs = duration?.inMilliseconds ?? 0;
    final watchedMs = watched.inMilliseconds;
    final watchPercent = durationMs > 0
        ? (watchedMs / durationMs * 100).clamp(0, 100).round()
        : null;
    return _postEvent(
      'feed_reel_progress',
      post,
      feedSurface: 'reels',
      position: position,
      metadata: {
        'watched_seconds': _seconds(watched),
        if (duration != null) 'duration_seconds': _seconds(duration),
        if (watchPercent != null) 'watch_percent': watchPercent,
      },
    );
  }

  static Future<void> _postEvent(
    String eventType,
    PostModel post, {
    required String feedSurface,
    int? position,
    Map<String, dynamic>? metadata,
  }) {
    return unawaitedEvent(
      ProductAnalytics.logEvent(
        eventType: eventType,
        entityType: 'post',
        entityId: post.id,
        metadata: {
          'feed_surface': feedSurface,
          'post_type': post.type,
          if (post.communityId != null) 'community_id': post.communityId,
          if (post.tags?.isNotEmpty == true) 'tags': post.tags!.take(8).toList(),
          if (position != null) 'position': position,
          ...?metadata,
        },
      ),
    );
  }

  static Future<void> unawaitedEvent(Future<void> future) async {
    unawaited(future);
  }

  static double _seconds(Duration duration) =>
      duration.inMilliseconds / Duration.millisecondsPerSecond;
}

class FeedExposureTracker extends StatefulWidget {
  const FeedExposureTracker({
    super.key,
    required this.post,
    required this.feedSurface,
    required this.position,
    required this.child,
  });

  final PostModel post;
  final String feedSurface;
  final int position;
  final Widget child;

  @override
  State<FeedExposureTracker> createState() => _FeedExposureTrackerState();
}

class _FeedExposureTrackerState extends State<FeedExposureTracker> {
  DateTime? _visibleSince;
  bool _impressionSent = false;
  bool _dwellSent = false;
  bool _skipSent = false;
  Timer? _dwellTimer;

  @override
  void dispose() {
    _finishExposure();
    _dwellTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;
    return VisibilityDetector(
      key: ValueKey('feed_exposure_${widget.feedSurface}_${widget.post.id}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final fraction = info.visibleFraction;
    if (fraction >= 0.55) {
      _startExposure();
    } else if (fraction <= 0.15) {
      _finishExposure();
    }
  }

  void _startExposure() {
    _visibleSince ??= DateTime.now();
    if (!_impressionSent) {
      _impressionSent = true;
      FeedAnalyticsService.impression(
        widget.post,
        feedSurface: widget.feedSurface,
        position: widget.position,
      );
    }
    _dwellTimer ??= Timer(FeedAnalyticsService.dwellThreshold, () {
      final startedAt = _visibleSince;
      if (startedAt == null || _dwellSent) return;
      _dwellSent = true;
      FeedAnalyticsService.dwell(
        widget.post,
        feedSurface: widget.feedSurface,
        duration: DateTime.now().difference(startedAt),
        position: widget.position,
      );
    });
  }

  void _finishExposure() {
    final startedAt = _visibleSince;
    if (startedAt == null) return;
    final duration = DateTime.now().difference(startedAt);
    if (duration < FeedAnalyticsService.skipThreshold && !_skipSent) {
      _skipSent = true;
      FeedAnalyticsService.skip(
        widget.post,
        feedSurface: widget.feedSurface,
        duration: duration,
        position: widget.position,
      );
    } else if (duration >= FeedAnalyticsService.dwellThreshold && !_dwellSent) {
      _dwellSent = true;
      FeedAnalyticsService.dwell(
        widget.post,
        feedSurface: widget.feedSurface,
        duration: duration,
        position: widget.position,
      );
    }
    _visibleSince = null;
    _dwellTimer?.cancel();
    _dwellTimer = null;
  }
}
