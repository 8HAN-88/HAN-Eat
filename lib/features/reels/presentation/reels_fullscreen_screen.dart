// Fullscreen Reels при тапе на видео в ленте — вертикальный свайп, возврат на то же место
import 'dart:async';
import 'dart:math' as math;
import '../../../utils/session_snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../models/post_model.dart';
import '../../../services/feed_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/comment_service.dart';
import '../../comments/presentation/show_post_comments_sheet.dart';
import '../../../utils/video_player_helper.dart';
import '../../../widgets/web_dom_video_layer.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../app/app_router.dart';
import '../../../utils/post_publisher_display.dart';
import '../../navigation/application/root_shell_chrome.dart';
import '../application/reels_swipe_policy.dart';
import '../application/reels_video_preload.dart';
import '../../settings/application/video_playback_controller.dart';
import '../../../services/subscription_status_cache.dart';
import '../../subscription/application/flex_entitlements.dart';
import '../../../models/video_quality_preference.dart';
import 'reels_feed_screen.dart';

class ReelsFullscreenScreen extends ConsumerStatefulWidget {
  final PostModel initialPost;

  const ReelsFullscreenScreen({
    super.key,
    required this.initialPost,
  });

  @override
  ConsumerState<ReelsFullscreenScreen> createState() =>
      _ReelsFullscreenScreenState();
}

class _ReelsFullscreenScreenState extends ConsumerState<ReelsFullscreenScreen>
    with WidgetsBindingObserver {
  late PageController _pageController;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _videoInitFailed = {};
  final Map<int, bool> _isPaused = {};
  List<PostModel> _reels = [];
  bool _isLoading = false;
  bool _loadMoreFailed = false;
  bool _hasMore = true;
  String? _nextCursor;
  int _currentIndex = 0;
  DateTime? _currentReelStartedAt;
  final Set<int> _impressedReelIds = {};
  bool _sessionMuted = kIsWeb;
  bool _appVisible = true;

  VideoQualityPreference get _playPref => flexReelQuality(
        ref.read(videoPlaybackProvider),
        priority: SubscriptionStatusCache.peek()
                ?.hasEntitlement('priority_reels_quality') ??
            false,
      );
  bool _openingComments = false;
  final Set<int> _videoInitInFlight = {};

  static const Duration _likeTouchGrace = Duration(seconds: 20);

  final Set<int> _likeBusy = {};
  final Map<int, DateTime> _likeTouchedAt = {};
  final Map<int, DateTime> _commentTouchedAt = {};

  bool get _canPlayVideos => _appVisible;

  bool _shouldPlayReelAt(int index) =>
      index == _currentIndex && _canPlayVideos && !(_isPaused[index] ?? false);

  void _playReelAt(int index) {
    final controller = _videoControllers[index];
    if (controller == null) return;
    unawaited(
      VideoPlayerHelper.ensurePlayingWithVolume(
        controller,
        muted: _sessionMuted,
        shouldContinue: () => mounted && _shouldPlayReelAt(index),
      ),
    );
  }

  Future<void> _reloadReelVideo(int index) async {
    if (index < 0 || index >= _reels.length) return;
    final controller = _videoControllers.remove(index);
    await controller?.dispose();
    if (!mounted) return;
    setState(() => _videoInitFailed.remove(index));
    await _initSingleVideo(index);
    if (mounted && _shouldPlayReelAt(index)) {
      _playReelAt(index);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hideShellBottomNavForFullscreenReels();
    _pageController = PageController(initialPage: 0);
    _pageController.addListener(_onPageScroll);
    _reels = [widget.initialPost];
    unawaited(_loadMoreReels());
    unawaited(_initializeVideos(0, 1, priorityIndex: 0));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startReelExposure(0);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (_appVisible == visible) return;
    _appVisible = visible;
    if (!visible) {
      _pauseAllVideos();
      return;
    }
    if (mounted) {
      _playReelAt(_currentIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clearRootShellBottomNavHide();
    _finishCurrentReelExposure();
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (var c in _videoControllers.values) {
      c.dispose();
    }
    _videoControllers.clear();
  }

  void _pauseAllVideos() {
    for (final c in _videoControllers.values) {
      c.pause();
    }
  }

  List<PostModel> _mergePreservingRecentLikes(List<PostModel> incoming) {
    if (_reels.isEmpty) return incoming;
    final existing = {for (final r in _reels) r.id: r};
    final now = DateTime.now();
    return incoming.map((post) {
      final prev = existing[post.id];
      if (prev == null) return post;
      var next = post;
      final likeTouched = _likeTouchedAt[post.id];
      if (likeTouched != null &&
          now.difference(likeTouched) < _likeTouchGrace) {
        next = next.copyWith(
          isLiked: prev.isLiked,
          likesCount: prev.likesCount,
        );
      }
      final commentTouched = _commentTouchedAt[post.id];
      if (commentTouched != null &&
          now.difference(commentTouched) < _likeTouchGrace) {
        next = next.copyWith(commentsCount: prev.commentsCount);
      }
      return next;
    }).toList();
  }

  Future<void> _loadMoreReels() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await FeedService.getFeed(
        cursor: _nextCursor,
        limit: 20,
        feedType: 'reels',
      );

      if (!mounted) return;

      final existingIds = _reels.map((r) => r.id).toSet();
      final newReels = _mergePreservingRecentLikes(
        response.items.where((r) => !existingIds.contains(r.id)).toList(),
      );

      final prevLen = _reels.length;

      setState(() {
        _reels.addAll(newReels);
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _isLoading = false;
        _loadMoreFailed = false;
      });

      if (newReels.isNotEmpty) {
        unawaited(
          _initializeVideos(
            prevLen,
            math.min(2, newReels.length),
            priorityIndex: _currentIndex,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadMoreFailed = true;
        });
      }
    }
  }

  Future<void> _initSingleVideo(int i) async {
    if (!mounted || !_canPlayVideos) return;
    if (_videoControllers.containsKey(i)) return;
    if (i < 0 || i >= _reels.length) return;
    if (!_videoInitInFlight.add(i)) return;

    try {
      final reel = _reels[i];
      final sources = reel.reelVideoSources;
      if (sources.isEmpty) {
        if (mounted) setState(() => _videoInitFailed[i] = true);
        return;
      }
      if (WebDomVideoLayer.isPreferred) {
        return;
      }

      try {
        final qualityPref = _playPref;
        final playback = await VideoPlayerHelper.createReelPlayback(
          sources: sources,
          qualityPref: qualityPref,
          autoPlay: false,
          muted: _sessionMuted,
        );

        if (!mounted) {
          playback.controller.dispose();
          return;
        }

        setState(() {
          _videoControllers[i] = playback.controller;
          _videoInitFailed.remove(i);
        });
        if (_shouldPlayReelAt(i)) {
          _playReelAt(i);
        } else {
          unawaited(playback.controller.pause());
        }

        final upgradeUrl = playback.upgradeUrl;
        if (upgradeUrl != null &&
            !ReelsSwipePolicy.skipQualityUpgrade(isWeb: kIsWeb)) {
          final controllerRef = playback.controller;
          VideoPlayerHelper.scheduleQualityUpgrade(
            current: controllerRef,
            upgradeUrl: upgradeUrl,
            shouldAutoPlay: () => _shouldPlayReelAt(i),
            onUpgraded: (upgraded) {
              if (!mounted) {
                return false;
              }
              if (_videoControllers[i] != controllerRef) {
                return false;
              }
              setState(() => _videoControllers[i] = upgraded);
              if (!_shouldPlayReelAt(i)) {
                unawaited(upgraded.pause());
              }
              return true;
            },
          );
        }
      } catch (e) {
        debugPrint('ReelsFullscreen init video $i: $e');
        if (mounted) setState(() => _videoInitFailed[i] = true);
      }
    } finally {
      _videoInitInFlight.remove(i);
    }
  }

  Future<void> _initializeVideos(
    int startIndex,
    int count, {
    int? priorityIndex,
  }) async {
    if (!_canPlayVideos) return;
    final end = math.min(startIndex + count, _reels.length);
    final indices = <int>[
      for (var i = startIndex; i < end; i++)
        if (!_videoControllers.containsKey(i)) i,
    ];
    await initializeReelVideosStaggered(
      indices: indices,
      priorityIndex: priorityIndex ?? _currentIndex,
      initSingle: _initSingleVideo,
    );
  }

  void _prefetchAdjacentReelFiles(int index) {
    final pref = _playPref;
    final urls = <String?>[
      if (index > 0) _reels[index - 1].reelVideoSources.prefetchUrl(pref),
      if (index + 1 < _reels.length)
        _reels[index + 1].reelVideoSources.prefetchUrl(pref),
      if (index + 2 < _reels.length)
        _reels[index + 2].reelVideoSources.prefetchUrl(pref),
    ];
    prefetchReelVideoUrls(urls);
  }

  void _trimVideoControllers() {
    final stale = _videoControllers.keys
        .where((i) => (i - _currentIndex).abs() > 2)
        .toList();
    for (final i in stale) {
      _videoControllers.remove(i)?.dispose();
      _isPaused.remove(i);
    }
  }

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null) return;
    final drifting = page - _currentIndex;
    if (drifting.abs() < 0.12) return;
    final neighbor = drifting > 0 ? _currentIndex + 1 : _currentIndex - 1;
    if (neighbor < 0 || neighbor >= _reels.length) return;
    if (_videoControllers.containsKey(neighbor)) return;
    unawaited(_initSingleVideo(neighbor));
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    _finishCurrentReelExposure();

    _videoControllers[_currentIndex]?.pause();
    _isPaused[_currentIndex] = false;
    _isPaused[index] = false;
    setState(() => _currentIndex = index);
    _startReelExposure(index);

    if (_videoControllers.containsKey(index)) {
      _playReelAt(index);
    } else {
      unawaited(
        _initializeVideos(index, 1, priorityIndex: index).then((_) {
          if (mounted && _canPlayVideos) _playReelAt(index);
        }),
      );
    }

    if (index >= _reels.length - 3 &&
        _hasMore &&
        !_isLoading &&
        !_loadMoreFailed) {
      _loadMoreReels();
    }
    if (_canPlayVideos && index + 1 < _reels.length) {
      unawaited(_initializeVideos(index + 1, 2, priorityIndex: index + 1));
    }
    _prefetchAdjacentReelFiles(index);
    unawaited(
      Future<void>.delayed(ReelsSwipePolicy.disposeAfterSettle, () {
        if (!mounted || _currentIndex != index) return;
        _trimVideoControllers();
      }),
    );
  }

  void _setSessionMuted(bool muted) {
    setState(() => _sessionMuted = muted);
    for (final controller in _videoControllers.values) {
      if (controller.value.isInitialized) {
        controller.setVolume(muted ? 0.0 : 1.0);
      }
    }
  }

  void _startReelExposure(int index) {
    if (index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    _currentReelStartedAt = DateTime.now();
    if (_impressedReelIds.add(reel.id)) {
      FeedAnalyticsService.impression(
        reel,
        feedSurface: 'reels_fullscreen',
        position: index,
      );
    }
  }

  void _finishCurrentReelExposure() {
    final startedAt = _currentReelStartedAt;
    if (startedAt == null ||
        _currentIndex < 0 ||
        _currentIndex >= _reels.length) {
      return;
    }

    final reel = _reels[_currentIndex];
    final watched = DateTime.now().difference(startedAt);
    final controller = _videoControllers[_currentIndex];
    final duration = controller != null && controller.value.isInitialized
        ? controller.value.duration
        : null;

    FeedAnalyticsService.reelProgress(
      reel,
      watched: watched,
      duration: duration,
      position: _currentIndex,
    );
    if (watched < FeedAnalyticsService.skipThreshold) {
      FeedAnalyticsService.skip(
        reel,
        feedSurface: 'reels_fullscreen',
        duration: watched,
        position: _currentIndex,
      );
    } else if (watched >= FeedAnalyticsService.dwellThreshold) {
      FeedAnalyticsService.dwell(
        reel,
        feedSurface: 'reels_fullscreen',
        duration: watched,
        position: _currentIndex,
      );
    }
    _currentReelStartedAt = null;
  }

  void _applyCommentsCount(int postId, int total) {
    final i = _reels.indexWhere((r) => r.id == postId);
    if (i == -1 || _reels[i].commentsCount == total) return;
    _commentTouchedAt[postId] = DateTime.now();
    _updateReelAt(
      postId,
      (r) => _copyReelWith(r, commentsCount: total),
    );
  }

  Future<void> _openComments(PostModel reel) async {
    if (_openingComments) return;
    _openingComments = true;
    FeedAnalyticsService.openDetail(
      reel,
      source: 'reels_fullscreen',
      target: 'comments',
    );
    _pauseAllVideos();
    try {
      final fromSheet = await showPostCommentsSheet(
        context,
        postId: reel.id,
        post: reel,
        onCommentsCountChanged: (total) {
          if (mounted) _applyCommentsCount(reel.id, total);
        },
      );
      if (!mounted) return;
      if (fromSheet != null) {
        _applyCommentsCount(reel.id, fromSheet);
      } else {
        try {
          final total = await CommentService.getCommentsTotal(reel.id);
          if (mounted) _applyCommentsCount(reel.id, total);
        } catch (_) {}
      }
      if (_canPlayVideos) {
        _playReelAt(_currentIndex);
      }
    } finally {
      _openingComments = false;
    }
  }

  Future<void> _toggleLike(int postId) async {
    if (_likeBusy.contains(postId)) return;
    final index = _reels.indexWhere((r) => r.id == postId);
    if (index == -1) return;

    final wasLiked = _reels[index].isLiked;
    _likeBusy.add(postId);
    _likeTouchedAt[postId] = DateTime.now();

    _updateReelAt(
      postId,
      (r) => _copyReelWith(
        r,
        isLiked: !wasLiked,
        likesCount: r.likesCount + (wasLiked ? -1 : 1),
      ),
    );

    try {
      final response = wasLiked
          ? await LikeService.unlikePost(postId)
          : await LikeService.likePost(postId);
      if (!mounted) return;
      _updateReelAt(
        postId,
        (r) => _copyReelWith(
          r,
          likesCount: response.likesCount,
          isLiked: response.liked,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _updateReelAt(
        postId,
        (r) => _copyReelWith(
          r,
          isLiked: wasLiked,
          likesCount: r.likesCount + (wasLiked ? 1 : -1),
        ),
      );
      showErrorSnackBar(
        context,
        e,
        onRetry: () => unawaited(_toggleLike(postId)),
      );
    } finally {
      _likeBusy.remove(postId);
    }
  }

  Future<void> _toggleSave(PostModel reel) async {
    try {
      final isSaved = reel.isSaved ?? false;
      if (isSaved) {
        await SavedPostsService.unsavePost(reel.id.toString());
      } else {
        await SavedPostsService.savePost(reel.id.toString());
      }
      _updateReelAt(reel.id, (r) => _copyReelWith(r, isSaved: !isSaved));
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e,
          onRetry: () => unawaited(_toggleSave(reel)),
        );
      }
    }
  }

  bool _isOwnReel(PostModel reel) {
    final me = AuthService.instance.currentUser?.id;
    return me != null && me == reel.userId;
  }

  Future<void> _toggleRepost(PostModel reel) async {
    if (!mounted) return;
    try {
      final isReposted = reel.isReposted ?? false;
      if (isReposted) {
        await RepostService.unrepost(reel.id.toString());
      } else {
        await RepostService.repost(reel.id.toString());
      }
      if (mounted) {
        _updateReelAt(
            reel.id, (r) => _copyReelWith(r, isReposted: !isReposted));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isReposted ? 'Репост отменён' : 'Репост выполнен')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('own post') || msg.contains('свой пост')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нельзя репостнуть свой пост')),
          );
        } else {
          showErrorSnackBar(
            context,
            e,
            fallback: 'Не удалось сделать репост',
            onRetry: () => unawaited(_toggleRepost(reel)),
          );
        }
      }
    }
  }

  PostModel _copyReelWith(
    PostModel r, {
    int? likesCount,
    int? commentsCount,
    bool? isLiked,
    bool? isSaved,
    bool? isReposted,
  }) {
    return PostModel(
      id: r.id,
      type: r.type,
      title: r.title,
      description: r.description,
      status: r.status,
      createdAt: r.createdAt,
      publishedAt: r.publishedAt,
      userId: r.userId,
      communityId: r.communityId,
      body: r.body,
      tags: r.tags,
      likesCount: likesCount ?? r.likesCount,
      commentsCount: commentsCount ?? r.commentsCount,
      repostsCount: r.repostsCount,
      viewsCount: r.viewsCount,
      isPromoted: r.isPromoted,
      isLiked: isLiked ?? r.isLiked,
      isSaved: isSaved ?? r.isSaved,
      isReposted: isReposted ?? r.isReposted,
      author: r.author,
      repostedBy: r.repostedBy,
      channel: r.channel,
    );
  }

  void _updateReelAt(int id, PostModel Function(PostModel) updater) {
    final idx = _reels.indexWhere((r) => r.id == id);
    if (idx != -1 && mounted) {
      setState(() {
        _reels[idx] = updater(_reels[idx]);
      });
    }
  }

  Future<void> _shareReel(PostModel reel) async {
    if (!mounted) return;
    await ShareActionSheet.showForReel(
      context,
      reel: reel,
      onRepostToWall:
          _isOwnReel(reel) ? null : () => _toggleRepost(reel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          WebDomVideoLayer.isPreferred ? Colors.transparent : Colors.black,
      body: Stack(
        children: [
          if (WebDomVideoLayer.isPreferred)
            const Positioned.fill(
              child: IgnorePointer(child: CanvasPunchHole()),
            ),
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            allowImplicitScrolling: true,
            padEnds: false,
            itemCount: _reels.length + (_hasMore ? 1 : 0),
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              if (index == _reels.length) {
                if (_loadMoreFailed) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Не удалось загрузить ещё рилсы',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => unawaited(_loadMoreReels()),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final reel = _reels[index];
              final card = ReelCard(
                key: ValueKey<int>(reel.id),
                reel: reel,
                index: index,
                videoController: _videoControllers[index],
                videoInitFailed: _videoInitFailed[index] == true,
                onRetryVideo: () => unawaited(_reloadReelVideo(index)),
                isCurrent: index == _currentIndex,
                playbackEnabled: _canPlayVideos,
                isPaused: _isPaused[index] ?? false,
                isMuted: _sessionMuted,
                onMutePreferenceChanged: _setSessionMuted,
                onPauseToggle: (paused) {
                  setState(() => _isPaused[index] = paused);
                },
                onLike: () => _toggleLike(reel.id),
                onComment: () => unawaited(_openComments(reel)),
                onShare: () => _shareReel(reel),
                onSave: () => _toggleSave(reel),
                onRepost:
                    _isOwnReel(reel) ? null : () => _toggleRepost(reel),
                onAuthorTap: () {
                  FeedAnalyticsService.openDetail(
                    reel,
                    source: 'reels_fullscreen',
                    target: PostPublisherDisplay.isChannel(reel)
                        ? 'channel'
                        : 'author',
                  );
                  PostPublisherDisplay.open(context, reel);
                },
                onHashtagTap: (tag) {
                  final q = tag.startsWith('#') ? tag : '#$tag';
                  context.push(
                    '${SearchRoute.path}?q=${Uri.encodeQueryComponent(q)}',
                  );
                },
                onMentionTap: (username, r) {
                  final uname = username.trim();
                  if (uname.isEmpty) return;
                  final author = r.author;
                  if (author?.username != null &&
                      author!.username!.toLowerCase() == uname.toLowerCase()) {
                    context.push('${ProfileRoute.path}?userId=${r.userId}');
                  } else {
                    context.push(
                      '${SearchRoute.path}?q=${Uri.encodeQueryComponent('@$uname')}',
                    );
                  }
                },
                onReport: () => reportPostWithDialog(context, reel.id),
                onQualityChanged: () => _reloadReelVideo(index),
              );
              if (WebDomVideoLayer.isPreferred) return card;
              return RepaintBoundary(child: card);
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
