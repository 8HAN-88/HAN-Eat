// Fullscreen Reels при тапе на видео в ленте — вертикальный свайп, возврат на то же место
import 'dart:async';
import 'dart:math' as math;
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../models/post_model.dart';
import '../../../services/feed_service.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../utils/video_player_helper.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../app/app_router.dart';
import '../../../utils/post_publisher_display.dart';
import '../../navigation/application/root_shell_chrome.dart';
import '../application/reels_video_preload.dart';
import '../../settings/application/video_playback_controller.dart';
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

class _ReelsFullscreenScreenState extends ConsumerState<ReelsFullscreenScreen> {
  late PageController _pageController;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _isPaused = {};
  List<PostModel> _reels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  int _currentIndex = 0;
  DateTime? _currentReelStartedAt;
  final Set<int> _impressedReelIds = {};
  bool _sessionMuted = false;

  static const Duration _likeTouchGrace = Duration(seconds: 20);

  final Set<int> _likeBusy = {};
  final Map<int, DateTime> _likeTouchedAt = {};

  bool _shouldPlayReelAt(int index) =>
      index == _currentIndex && !(_isPaused[index] ?? false);

  void _playReelAt(int index) {
    final controller = _videoControllers[index];
    if (controller == null) return;
    unawaited(
      VideoPlayerHelper.ensurePlaying(
        controller,
        shouldContinue: () => mounted && _shouldPlayReelAt(index),
      ),
    );
  }

  Future<void> _reloadReelVideo(int index) async {
    if (index < 0 || index >= _reels.length) return;
    final controller = _videoControllers.remove(index);
    await controller?.dispose();
    if (!mounted) return;
    await _initSingleVideo(index);
    if (mounted && _shouldPlayReelAt(index)) {
      _playReelAt(index);
    }
  }

  @override
  void initState() {
    super.initState();
    hideShellBottomNavForFullscreenReels();
    _pageController = PageController(initialPage: 0);
    _reels = [widget.initialPost];
    unawaited(_loadMoreReels());
    unawaited(_initializeVideos(0, 1, priorityIndex: 0));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startReelExposure(0);
    });
  }

  @override
  void dispose() {
    clearRootShellBottomNavHide();
    _finishCurrentReelExposure();
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

  List<PostModel> _mergePreservingRecentLikes(List<PostModel> incoming) {
    if (_reels.isEmpty) return incoming;
    final existing = {for (final r in _reels) r.id: r};
    final now = DateTime.now();
    return incoming.map((post) {
      final prev = existing[post.id];
      if (prev == null) return post;
      final touched = _likeTouchedAt[post.id];
      if (touched != null && now.difference(touched) < _likeTouchGrace) {
        return post.copyWith(
          isLiked: prev.isLiked,
          likesCount: prev.likesCount,
        );
      }
      return post;
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initSingleVideo(int i) async {
    if (!mounted) return;
    if (_videoControllers.containsKey(i)) return;
    if (i < 0 || i >= _reels.length) return;

    final reel = _reels[i];
    final sources = reel.reelVideoSources;
    if (sources.isEmpty) return;

    try {
      final shouldPlay = _shouldPlayReelAt(i);
      final qualityPref = ref.read(videoPlaybackProvider);
      final playback = await VideoPlayerHelper.createReelPlayback(
        sources: sources,
        qualityPref: qualityPref,
        autoPlay: shouldPlay,
        muted: _sessionMuted,
      );

      if (!mounted) {
        playback.controller.dispose();
        return;
      }

      setState(() {
        _videoControllers[i] = playback.controller;
      });

      final upgradeUrl = playback.upgradeUrl;
      if (upgradeUrl != null) {
        final controllerRef = playback.controller;
        VideoPlayerHelper.scheduleQualityUpgrade(
          current: controllerRef,
          upgradeUrl: upgradeUrl,
          shouldAutoPlay: () => _shouldPlayReelAt(i),
          onUpgraded: (upgraded) {
            if (!mounted) {
              upgraded.dispose();
              return;
            }
            if (_videoControllers[i] != controllerRef) {
              upgraded.dispose();
              return;
            }
            setState(() => _videoControllers[i] = upgraded);
            if (!_shouldPlayReelAt(i)) {
              unawaited(upgraded.pause());
            }
          },
        );
      }
    } catch (e) {
      debugPrint('ReelsFullscreen init video $i: $e');
    }
  }

  Future<void> _initializeVideos(
    int startIndex,
    int count, {
    int? priorityIndex,
  }) async {
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
    final pref = ref.read(videoPlaybackProvider);
    final urls = <String?>[
      if (index > 0)
        _reels[index - 1].reelVideoSources.prefetchUrl(pref),
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

  void _onPageChanged(int index) {
    _finishCurrentReelExposure();

    _videoControllers[_currentIndex]?.pause();
    setState(() => _isPaused[_currentIndex] = true);

    setState(() {
      _currentIndex = index;
      _isPaused[index] = false;
    });
    _startReelExposure(index);

    if (_videoControllers.containsKey(index)) {
      _playReelAt(index);
    } else {
      unawaited(
        _initializeVideos(index, 1, priorityIndex: index).then((_) {
          if (mounted) _playReelAt(index);
        }),
      );
    }

    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadMoreReels();
    }
    if (index + 1 < _reels.length) {
      unawaited(_initializeVideos(index + 1, 3, priorityIndex: index));
    }
    _prefetchAdjacentReelFiles(index);
    _trimVideoControllers();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userVisibleError(e))));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userVisibleError(e))));
      }
    }
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
          showErrorSnackBar(context, e, fallback: 'Не удалось сделать репост');
        }
      }
    }
  }

  PostModel _copyReelWith(
    PostModel r, {
    int? likesCount,
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
      commentsCount: r.commentsCount,
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
      onRepostToWall: () => _toggleRepost(reel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _reels.length + (_hasMore ? 1 : 0),
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              if (index == _reels.length) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final reel = _reels[index];
              return ReelCard(
                reel: reel,
                index: index,
                videoController: _videoControllers[index],
                isCurrent: index == _currentIndex,
                isPaused: _isPaused[index] ?? false,
                isMuted: _sessionMuted,
                onMutePreferenceChanged: _setSessionMuted,
                onPauseToggle: (paused) {
                  setState(() => _isPaused[index] = paused);
                },
                onLike: () => _toggleLike(reel.id),
                onComment: () {
                  FeedAnalyticsService.openDetail(
                    reel,
                    source: 'reels_fullscreen',
                    target: 'comments',
                  );
                  context.push('/post/${reel.id}/comments');
                },
                onShare: () => _shareReel(reel),
                onSave: () => _toggleSave(reel),
                onRepost: () => _toggleRepost(reel),
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
