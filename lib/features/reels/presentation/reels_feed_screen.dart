// Экран Reels Feed с вертикальной прокруткой (как TikTok/Instagram Reels)
import 'dart:async';
import '../../../utils/api_error_parser.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/network/feed_connectivity.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../models/post_model.dart';
import '../../../services/feed_api_cache.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/server_config.dart';
import 'package:go_router/go_router.dart';
import '../../../services/like_service.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/repost_service.dart';
import '../../../utils/video_player_helper.dart';
import '../../../widgets/cover_network_video.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/share_action_sheet.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../app/app_router.dart';
import '../../../utils/post_publisher_display.dart';
import '../application/reels_feed_refresh_provider.dart';

class ReelsFeedScreen extends ConsumerStatefulWidget {
  const ReelsFeedScreen({
    super.key,
    this.hideScaffold = false,
    this.isTabVisible = true,
    this.externalFollowingOnly = false,
  });

  /// Без вложенного Scaffold (вкладка «Рилсы» в [MainFeedScreen]).
  final bool hideScaffold;

  /// false на вкладке «Рилсы», пока пользователь на другом табе — не грузим API/видео.
  final bool isTabVisible;

  /// Фильтр «Подписки» с родителя ([MainFeedScreen]).
  final bool externalFollowingOnly;

  @override
  ConsumerState<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends ConsumerState<ReelsFeedScreen> {
  final PageController _pageController = PageController();
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _isPaused = {}; // Состояние паузы для каждого видео
  final Map<int, bool> _videoInitFailed = {};
  List<PostModel> _reels = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  int _currentIndex = 0;
  String? _lastLoadError;
  bool _loadKickoff = false;
  bool _servingFromCache = false;
  Object? _cacheLoadError;
  DateTime? _currentReelStartedAt;
  final Set<int> _impressedReelIds = {};
  bool _sessionMuted = false;

  bool _followingOnly = false;

  String get _cacheVariant =>
      _followingOnly ? 'rec_reels_following' : 'rec_reels';

  int get _initialVideoPreloadCount => kIsWeb ? 1 : 3;

  int get _lookaheadVideoPreloadCount => kIsWeb ? 0 : 2;

  @override
  void initState() {
    super.initState();
    _followingOnly = widget.externalFollowingOnly;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLoadIfNeeded());
  }

  @override
  void didUpdateWidget(ReelsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalFollowingOnly != oldWidget.externalFollowingOnly &&
        widget.externalFollowingOnly != _followingOnly) {
      _followingOnly = widget.externalFollowingOnly;
      if (widget.isTabVisible) {
        _loadReels(refresh: true);
      }
    }
    if (widget.isTabVisible && !oldWidget.isTabVisible) {
      _startLoadIfNeeded();
      if (_reels.isNotEmpty) {
        _initializeVideos(
          _currentIndex,
          math.min(_initialVideoPreloadCount, _reels.length - _currentIndex),
        );
        final c = _videoControllers[_currentIndex];
        if (c != null) VideoPlayerHelper.ensurePlaying(c);
      }
    } else if (!widget.isTabVisible && oldWidget.isTabVisible) {
      _pauseAllVideos();
    }
  }

  void _startLoadIfNeeded() {
    if (!mounted || !widget.isTabVisible) return;
    if (_loadKickoff) return;
    setState(() => _loadKickoff = true);
    _loadReels(refresh: true);
  }

  void _pauseAllVideos() {
    for (final c in _videoControllers.values) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _finishCurrentReelExposure();
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
  }

  Future<void> _loadReels({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _reels = [];
        _nextCursor = null;
        _hasMore = true;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
        _currentReelStartedAt = null;
        _impressedReelIds.clear();
        _videoInitFailed.clear();
        _disposeAllControllers();
      }
    });

    if (refresh && !feedDeviceOnline()) {
      final cached = await FeedApiCache.load(_cacheVariant);
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _reels = cached;
          _nextCursor = null;
          _hasMore = false;
          _lastLoadError = null;
          _servingFromCache = true;
          _cacheLoadError = 'offline';
          _isLoading = false;
        });
        if (_reels.isNotEmpty) {
          _initializeVideos(0, math.min(_initialVideoPreloadCount, _reels.length));
        }
        return;
      }
    }

    try {
      final response = await FeedService.getFeed(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
        feedType: 'reels',
        followingOnly: _followingOnly,
      );

      if (!mounted) return;
      final nextReels =
          refresh ? response.items : <PostModel>[..._reels, ...response.items];
      setState(() {
        _reels = nextReels;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
      });
      await FeedApiCache.save(_cacheVariant, nextReels);

      if (_reels.isNotEmpty) {
        _initializeVideos(0, math.min(_initialVideoPreloadCount, _reels.length));
        _startReelExposure(_currentIndex);
      }
    } catch (e) {
      if (mounted) {
        if (FeedLoadHelper.isSessionError(e)) {
          await FeedLoadHelper.clearSessionIfExpired(e);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сессия истекла. Войдите снова.')),
          );
          return;
        }
        final cached = await FeedApiCache.load(_cacheVariant);
        if (!mounted) return;
        if (cached.isNotEmpty) {
          setState(() {
            _reels = cached;
            _nextCursor = null;
            _hasMore = false;
            _lastLoadError = null;
            _servingFromCache = true;
            _cacheLoadError = e;
          });
          if (_reels.isNotEmpty) {
            _initializeVideos(0, math.min(_initialVideoPreloadCount, _reels.length));
            _startReelExposure(_currentIndex);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FeedLoadHelper.cacheSnackMessage(e))),
          );
        } else {
          final short = e is TimeoutException
              ? 'Сервер не ответил вовремя. Проверьте подключение и попробуйте снова.'
              : userVisibleError(e, fallback: 'Не удалось загрузить рилсы');
          setState(() => _lastLoadError = short);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(short)),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initializeVideos(int startIndex, int count) async {
    if (!widget.isTabVisible) return;
    for (int i = startIndex; i < startIndex + count && i < _reels.length; i++) {
      final reel = _reels[i];
      if (_videoControllers.containsKey(i)) continue;

      final videoUrl = reel.videoUrl;
      if (videoUrl == null || videoUrl.isEmpty) {
        if (mounted) {
          setState(() => _videoInitFailed[i] = true);
        }
        continue;
      }
      try {
        final shouldPlay = i == _currentIndex && widget.isTabVisible;
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
          _videoInitFailed.remove(i);
        });
      } catch (e) {
        debugPrint('Ошибка инициализации видео $i ($videoUrl): $e');
        if (mounted) {
          setState(() => _videoInitFailed[i] = true);
        }
      }
    }
  }

  void _onPageChanged(int index) {
    _finishCurrentReelExposure();

    // Останавливаем предыдущее видео
    _videoControllers[_currentIndex]?.pause();
    setState(() {
      _isPaused[_currentIndex] = true;
    });

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

    // Загружаем больше, если приближаемся к концу
    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadReels();
    }

    // Предзагружаем следующие видео (на web только текущий)
    if (_lookaheadVideoPreloadCount > 0 && index + 1 < _reels.length) {
      _initializeVideos(index + 1, _lookaheadVideoPreloadCount);
    }
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

  void _trimVideoControllers() {
    final stale = _videoControllers.keys
        .where((i) => (i - _currentIndex).abs() > 1)
        .toList();
    for (final i in stale) {
      _videoControllers.remove(i)?.dispose();
      _isPaused.remove(i);
      _videoInitFailed.remove(i);
    }
  }

  void _startReelExposure(int index) {
    if (index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    _currentReelStartedAt = DateTime.now();
    if (_impressedReelIds.add(reel.id)) {
      FeedAnalyticsService.impression(
        reel,
        feedSurface: 'reels',
        position: index,
      );
    }
  }

  void _finishCurrentReelExposure() {
    final startedAt = _currentReelStartedAt;
    if (startedAt == null || _currentIndex < 0 || _currentIndex >= _reels.length) {
      return;
    }
    final reel = _reels[_currentIndex];
    final watched = DateTime.now().difference(startedAt);
    final controller = _videoControllers[_currentIndex];
    final duration =
        controller != null && controller.value.isInitialized
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
        feedSurface: 'reels',
        duration: watched,
        position: _currentIndex,
      );
    } else if (watched >= FeedAnalyticsService.dwellThreshold) {
      FeedAnalyticsService.dwell(
        reel,
        feedSurface: 'reels',
        duration: watched,
        position: _currentIndex,
      );
    }
    _currentReelStartedAt = null;
  }

  Widget _buildEmptyState() {
    final empty = RefreshIndicator(
      onRefresh: () => _loadReels(refresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: _lastLoadError != null
                  ? Icons.cloud_off_outlined
                  : Icons.video_library_outlined,
              title: _lastLoadError != null
                  ? 'Не удалось загрузить рилсы'
                  : 'Пока нет рилсов',
              subtitle: _lastLoadError ??
                  'Рилсы публикуются из каналов — откройте канал и нажмите «+».',
              action: _lastLoadError != null
                  ? FilledButton.icon(
                      onPressed: () => _loadReels(refresh: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );

    if (widget.hideScaffold) return empty;

    return Scaffold(
      appBar: AppBar(title: const Text('Рилсы')),
      body: empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(reelsFeedRefreshProvider, (prev, next) {
      if (prev != null && prev != next) {
        _loadReels(refresh: true);
      }
    });

    if (_reels.isEmpty && _isLoading) {
      final loading = const Center(child: CircularProgressIndicator());
      if (widget.hideScaffold) return loading;
      return Scaffold(body: loading);
    }

    if (_reels.isEmpty) {
      return _buildEmptyState();
    }

    final topPad = MediaQuery.paddingOf(context).top;
    final pageBody = Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _reels.length + (_hasMore ? 1 : 0),
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) {
            if (index == _reels.length) {
              // Индикатор загрузки в конце
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            final reel = _reels[index];
            return ReelCard(
              reel: reel,
              index: index,
              videoController: _videoControllers[index],
              videoInitFailed: _videoInitFailed[index] == true,
              onRetryVideo: () {
                setState(() => _videoInitFailed.remove(index));
                _initializeVideos(index, 1);
              },
              isCurrent: index == _currentIndex,
              isPaused: _isPaused[index] ?? false,
              isMuted: _sessionMuted,
              onMutePreferenceChanged: _setSessionMuted,
              onPauseToggle: (paused) {
                setState(() {
                  _isPaused[index] = paused;
                });
              },
              onLike: () => _toggleLike(reel),
              onComment: () {
                FeedAnalyticsService.openDetail(
                  reel,
                  source: 'reels',
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
                  source: 'reels',
                  target: PostPublisherDisplay.isChannel(reel)
                      ? 'channel'
                      : 'author',
                );
                PostPublisherDisplay.open(context, reel);
              },
              onHashtagTap: (tag) {
                final q = tag.startsWith('#') ? tag : '#$tag';
                context.push(
                    '${SearchRoute.path}?q=${Uri.encodeQueryComponent(q)}');
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
        if (_servingFromCache)
          Positioned(
            top: topPad + 6,
            left: 10,
            right: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.offline_pin_outlined,
                        color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Кеш · без сети видео может не воспроизвестись',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final reelFeed = kIsWeb
        ? ColoredBox(
            color: Colors.black,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: pageBody,
                ),
              ),
            ),
          )
        : pageBody;

    if (widget.hideScaffold) {
      return reelFeed;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: reelFeed,
    );
  }

  Future<void> _toggleLike(PostModel reel) async {
    try {
      final wasLiked = reel.isLiked;
      final response = wasLiked
          ? await LikeService.unlikePost(reel.id)
          : await LikeService.likePost(reel.id);
      setState(() {
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = _reels[index].copyWith(
            likesCount: response.likesCount,
            isLiked: response.liked,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
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
      setState(() {
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = _reels[index].copyWith(isSaved: !isSaved);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _toggleRepost(PostModel reel) async {
    try {
      final isReposted = reel.isReposted ?? false;
      if (isReposted) {
        await RepostService.unrepost(reel.id.toString());
      } else {
        await RepostService.repost(reel.id.toString());
      }
      setState(() {
        final index = _reels.indexWhere((r) => r.id == reel.id);
        if (index != -1) {
          _reels[index] = _reels[index].copyWith(isReposted: !isReposted);
        }
      });
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

  Future<void> _shareReel(PostModel reel) async {
    await ShareActionSheet.showForReel(
      context,
      reel: reel,
      onRepostToWall: () => _toggleRepost(reel),
    );
  }
}

class ReelCard extends StatefulWidget {
  final PostModel reel;
  final int index;
  final VideoPlayerController? videoController;
  final bool videoInitFailed;
  final VoidCallback? onRetryVideo;
  final bool isCurrent;
  final bool isPaused;
  final bool isMuted;
  final ValueChanged<bool> onMutePreferenceChanged;
  final ValueChanged<bool> onPauseToggle;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onRepost;
  final VoidCallback onAuthorTap;
  final void Function(String tagWithoutHash) onHashtagTap;
  final void Function(String usernameWithoutAt, PostModel reel) onMentionTap;
  final VoidCallback onReport;

  const ReelCard({
    super.key,
    required this.reel,
    required this.index,
    this.videoController,
    this.videoInitFailed = false,
    this.onRetryVideo,
    required this.isCurrent,
    required this.isPaused,
    required this.isMuted,
    required this.onMutePreferenceChanged,
    required this.onPauseToggle,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onRepost,
    required this.onAuthorTap,
    required this.onHashtagTap,
    required this.onMentionTap,
    required this.onReport,
  });

  @override
  State<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<ReelCard>
    with SingleTickerProviderStateMixin {
  DateTime? _lastTap;
  bool _showLikeAnimation = false;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;
  late Animation<double> _likeOpacityAnimation;
  final List<TapGestureRecognizer> _descriptionRecognizers = [];
  VideoPlayerController? _progressController;

  static const double _igIconSize = 28;
  static const double _igActionGap = 18;
  static const double _igRightInset = 12;
  static const double _igRailWidth = 52;

  @override
  void initState() {
    super.initState();
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 0.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _likeOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _likeAnimationController,
        curve: const Interval(0.5, 1.0),
      ),
    );
    _attachProgressListener(widget.videoController);
  }

  @override
  void dispose() {
    _detachProgressListener();
    for (final r in _descriptionRecognizers) {
      r.dispose();
    }
    _descriptionRecognizers.clear();
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _detachProgressListener() {
    _progressController?.removeListener(_onVideoProgress);
    _progressController = null;
  }

  void _attachProgressListener(VideoPlayerController? controller) {
    if (_progressController == controller) return;
    _progressController?.removeListener(_onVideoProgress);
    _progressController = controller;
    _progressController?.addListener(_onVideoProgress);
  }

  void _onVideoProgress() {
    if (mounted) setState(() {});
  }

  double get _playbackProgress {
    final controller = widget.videoController;
    if (controller == null || !controller.value.isInitialized) return 0;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) return 0;
    return (controller.value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                (widget.reel.isSaved ?? false)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              title: Text(
                (widget.reel.isSaved ?? false) ? 'Убрать из сохранённых' : 'Сохранить',
              ),
              onTap: () {
                Navigator.pop(ctx);
                widget.onSave();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Пожаловаться'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onReport();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _clearDescriptionRecognizers() {
    for (final r in _descriptionRecognizers) {
      r.dispose();
    }
    _descriptionRecognizers.clear();
  }

  void _handleDoubleTap() {
    if (!widget.reel.isLiked) {
      widget.onLike();
      setState(() {
        _showLikeAnimation = true;
      });
      _likeAnimationController.forward().then((_) {
        if (mounted) {
          setState(() {
            _showLikeAnimation = false;
          });
          _likeAnimationController.reset();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attachProgressListener(widget.videoController);
  }

  Future<void> _toggleMute() async {
    widget.onMutePreferenceChanged(!widget.isMuted);
  }

  void _handleSingleTap() {
    final now = DateTime.now();
    if (_lastTap != null &&
        now.difference(_lastTap!) < const Duration(milliseconds: 300)) {
      _handleDoubleTap();
      _lastTap = null;
      return;
    }
    _lastTap = now;

    if (widget.videoController != null) {
      VideoPlayerHelper.toggleOrStart(widget.videoController!).then((paused) {
        if (mounted) widget.onPauseToggle(paused);
      });
    }
  }

  Widget _buildVideoPlaceholder() {
    if (widget.videoInitFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined,
              color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Не удалось загрузить видео',
            style: TextStyle(color: Colors.white70),
          ),
          if (widget.onRetryVideo != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onRetryVideo,
              child: const Text('Повторить'),
            ),
          ],
        ],
      );
    }

    final thumb = widget.reel.videoThumbnail;
    if (thumb != null && thumb.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            memCacheWidth: 860,
            placeholder: (_, __) => Container(color: Colors.grey[900]),
            errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
          ),
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ],
      );
    }

    return const CircularProgressIndicator(color: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final publisherAvatar = PostPublisherDisplay.avatarUrl(reel);
    final publisherInitial = PostPublisherDisplay.avatarInitial(reel);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final railBottom = bottomSafe + 96;
    final contentBottom = bottomSafe + 8;

    return GestureDetector(
      onTap: _handleSingleTap,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.videoController != null)
            SizedBox.expand(
              child: CoverNetworkVideo(controller: widget.videoController!),
            )
          else
            Container(
              color: Colors.black,
              child: Center(child: _buildVideoPlaceholder()),
            ),

          Positioned(
            left: 0,
            top: 0,
            right: _igRailWidth + _igRightInset,
            bottom: 0,
            child: GestureDetector(
              onTap: _handleSingleTap,
              onDoubleTap: _handleDoubleTap,
              behavior: HitTestBehavior.opaque,
            ),
          ),

          if (widget.isPaused)
            Positioned(
              left: 0,
              top: 0,
              right: _igRailWidth + _igRightInset,
              bottom: 0,
              child: GestureDetector(
                onTap: _handleSingleTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.videoController != null) ...[
                        GestureDetector(
                          onTap: _toggleMute,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      GestureDetector(
                        onTap: _handleSingleTap,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_showLikeAnimation)
            Center(
              child: AnimatedBuilder(
                animation: _likeAnimationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _likeOpacityAnimation.value,
                    child: Transform.scale(
                      scale: _likeScaleAnimation.value,
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 100,
                      ),
                    ),
                  );
                },
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            right: _igRightInset,
            bottom: railBottom,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IgReelAction(
                    icon: widget.reel.isLiked
                        ? Icons.favorite
                        : Icons.favorite_border,
                    count: widget.reel.likesCount,
                    onTap: widget.onLike,
                    color: widget.reel.isLiked ? const Color(0xFFFF3040) : Colors.white,
                  ),
                  const SizedBox(height: _igActionGap),
                  _IgReelAction(
                    icon: Icons.mode_comment_outlined,
                    count: widget.reel.commentsCount,
                    onTap: widget.onComment,
                  ),
                  const SizedBox(height: _igActionGap),
                  _IgReelAction(
                    icon: (widget.reel.isReposted ?? false)
                        ? Icons.repeat_on
                        : Icons.repeat,
                    count: widget.reel.repostsCount,
                    onTap: widget.onRepost,
                    color: (widget.reel.isReposted ?? false)
                        ? const Color(0xFF4CD964)
                        : Colors.white,
                  ),
                  const SizedBox(height: _igActionGap),
                  _IgReelAction(
                    icon: Icons.near_me_outlined,
                    onTap: widget.onShare,
                    showCount: false,
                  ),
                  const SizedBox(height: _igActionGap),
                  _IgReelAction(
                    icon: Icons.more_horiz,
                    onTap: _showMoreMenu,
                    showCount: false,
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            left: 12,
            right: _igRailWidth + _igRightInset + 8,
            bottom: contentBottom + 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onAuthorTap,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: ClipOval(
                          child: publisherAvatar != null
                              ? CachedNetworkImage(
                                  imageUrl:
                                      ServerConfig.resolvePublisherAvatarUrl(
                                    publisherAvatar,
                                  ),
                                  fit: BoxFit.cover,
                                  memCacheWidth: 64,
                                  placeholder: (_, __) =>
                                      ColoredBox(color: Colors.grey[800]!),
                                  errorWidget: (_, __, ___) => ColoredBox(
                                    color: Colors.grey[800]!,
                                    child: Center(
                                      child: Text(
                                        publisherInitial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : ColoredBox(
                                  color: Colors.grey[800]!,
                                  child: Center(
                                    child: Text(
                                      publisherInitial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.onAuthorTap,
                        child: Text(
                          PostPublisherDisplay.atLabel(reel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onAuthorTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Text(
                          'Подписаться',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.reel.description != null &&
                    widget.reel.description!.isNotEmpty)
                  _buildDescription(widget.reel.description!),
                if (widget.reel.tags != null &&
                    widget.reel.tags!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.reel.tags!.map((tag) {
                      return GestureDetector(
                        onTap: () => widget.onHashtagTap(tag),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          if (widget.videoController != null &&
              widget.videoController!.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: _playbackProgress,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDescription(String description) {
    _clearDescriptionRecognizers();
    final words = description.split(' ');
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.4,
        ),
        children: words.map((word) {
          if (word.startsWith('#')) {
            final tag = word.substring(1).replaceAll(RegExp(r'[^\w]+$'), '');
            if (tag.isEmpty) {
              return TextSpan(text: '$word ');
            }
            final r = TapGestureRecognizer()
              ..onTap = () => widget.onHashtagTap(tag);
            _descriptionRecognizers.add(r);
            return TextSpan(
              text: '$word ',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: r,
            );
          }
          if (word.startsWith('@')) {
            final username =
                word.substring(1).replaceAll(RegExp(r'[^\w._]+$'), '');
            if (username.isEmpty) {
              return TextSpan(text: '$word ');
            }
            final r = TapGestureRecognizer()
              ..onTap = () => widget.onMentionTap(username, widget.reel);
            _descriptionRecognizers.add(r);
            return TextSpan(
              text: '$word ',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: r,
            );
          }
          return TextSpan(text: '$word ');
        }).toList(),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _IgReelAction extends StatelessWidget {
  const _IgReelAction({
    required this.icon,
    required this.onTap,
    this.count = 0,
    this.color,
    this.showCount = true,
  });

  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? color;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final showNumber = showCount;

    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              icon,
              color: color ?? Colors.white,
              size: 28,
            ),
          ),
          if (showNumber) ...[
            const SizedBox(height: 3),
            Text(
              NumberFormatter.formatCount(count),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
