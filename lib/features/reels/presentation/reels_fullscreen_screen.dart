// Fullscreen Reels при тапе на видео в ленте — вертикальный свайп, возврат на то же место
import 'dart:math' as math;
import '../../../utils/api_error_parser.dart';
import 'package:flutter/material.dart';
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
import 'reels_feed_screen.dart';

class ReelsFullscreenScreen extends StatefulWidget {
  final PostModel initialPost;

  const ReelsFullscreenScreen({
    super.key,
    required this.initialPost,
  });

  @override
  State<ReelsFullscreenScreen> createState() => _ReelsFullscreenScreenState();
}

class _ReelsFullscreenScreenState extends State<ReelsFullscreenScreen> {
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _reels = [widget.initialPost];
    _loadMoreReels();
    _initializeVideos(0, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startReelExposure(0);
    });
  }

  @override
  void dispose() {
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
      final newReels =
          response.items.where((r) => !existingIds.contains(r.id)).toList();

      setState(() {
        _reels.addAll(newReels);
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _isLoading = false;
      });

      if (newReels.isNotEmpty) {
        _initializeVideos(1, math.min(3, _reels.length));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initializeVideos(int startIndex, int count) async {
    for (int i = startIndex; i < startIndex + count && i < _reels.length; i++) {
      if (_videoControllers.containsKey(i)) continue;

      final reel = _reels[i];
      final videoUrl = reel.videoUrl;
      if (videoUrl == null || videoUrl.isEmpty) continue;

      try {
        final shouldPlay = i == _currentIndex;
        final videoController = await VideoPlayerHelper.createPreparedController(
          videoUrl,
          autoPlay: shouldPlay,
          muted: _sessionMuted,
        );

        if (!mounted) {
          videoController.dispose();
          return;
        }

        setState(() {
          _videoControllers[i] = videoController;
        });
      } catch (e) {
        debugPrint('ReelsFullscreen init video $i: $e');
      }
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
      VideoPlayerHelper.ensurePlaying(_videoControllers[index]!);
    } else {
      _initializeVideos(index, 1).then((_) {
        final c = _videoControllers[index];
        if (mounted && c != null) VideoPlayerHelper.ensurePlaying(c);
      });
    }

    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadMoreReels();
    }
    if (index + 1 < _reels.length) {
      _initializeVideos(index + 1, 2);
    }
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

  Future<void> _toggleLike(PostModel reel) async {
    try {
      final wasLiked = reel.isLiked;
      final response = wasLiked
          ? await LikeService.unlikePost(reel.id)
          : await LikeService.likePost(reel.id);
      _updateReelAt(
        reel.id,
        (r) => _copyReelWith(
          r,
          likesCount: response.likesCount,
          isLiked: response.liked,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userVisibleError(e))));
      }
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
        final text = msg.contains('own post') || msg.contains('свой пост')
            ? 'Нельзя репостнуть свой пост'
            : userVisibleAuthError(
                e,
                fallback: 'Не удалось сделать репост',
                authFallback: 'Войдите, чтобы сделать репост',
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
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
                onLike: () => _toggleLike(reel),
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
