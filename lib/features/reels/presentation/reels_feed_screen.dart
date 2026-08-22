// Экран Reels Feed с вертикальной прокруткой (как TikTok/Instagram Reels)
import 'dart:async';
import '../../../utils/api_error_parser.dart';
import '../../../utils/session_snackbar.dart';
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
import '../../../models/video_quality_preference.dart';
import '../../../services/feed_api_cache.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/user_realtime_service.dart';
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
import '../../../widgets/custom_emoji_view.dart';
import '../../../app/app_router.dart';
import '../../../utils/post_publisher_display.dart';
import '../../navigation/application/root_shell_chrome.dart';
import '../application/reels_feed_refresh_provider.dart';
import '../application/reels_video_preload.dart';
import '../../settings/application/video_playback_controller.dart';

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

class _ReelsFeedScreenState extends ConsumerState<ReelsFeedScreen>
    with WidgetsBindingObserver {
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
  int _loadGeneration = 0;
  bool _servingFromCache = false;
  Object? _cacheLoadError;
  DateTime? _currentReelStartedAt;
  final Set<int> _impressedReelIds = {};
  bool _sessionMuted = false;
  bool _appVisible = true;

  static const Duration _likeTouchGrace = Duration(seconds: 20);

  final Set<int> _likeBusy = {};
  final Map<int, DateTime> _likeTouchedAt = {};

  bool _followingOnly = false;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;

  String get _cacheVariant =>
      _followingOnly ? 'rec_reels_following' : 'rec_reels';

  int get _initialVideoPreloadCount => 2;

  int get _lookaheadVideoPreloadCount => 2;

  int get _controllerRetainDistance => 2;

  bool get _canPlayVideos => widget.isTabVisible && _appVisible;

  bool _shouldPlayReelAt(int index) =>
      index == _currentIndex && _canPlayVideos && !(_isPaused[index] ?? false);

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
    setState(() => _videoInitFailed.remove(index));
    await _initSingleVideo(index);
    if (mounted && _shouldPlayReelAt(index)) {
      _playReelAt(index);
    }
  }

  Future<void> _initSingleVideo(int i) async {
    if (!mounted || !_canPlayVideos) return;
    if (_videoControllers.containsKey(i)) return;
    if (i < 0 || i >= _reels.length) return;

    final reel = _reels[i];
    final sources = reel.reelVideoSources;
    if (sources.isEmpty) {
      if (mounted) setState(() => _videoInitFailed[i] = true);
      return;
    }
    try {
      final qualityPref = ref.read(videoPlaybackProvider);
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

      if (i == _currentIndex) {
        _prefetchAdjacentReelFiles(i);
        _scheduleNeighborControllers(i);
      }
      if (_shouldPlayReelAt(i)) {
        _playReelAt(i);
      } else {
        unawaited(playback.controller.pause());
      }

      final upgradeUrl = playback.upgradeUrl;
      if (upgradeUrl != null) {
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
      final startUrl = sources.fastStartUrl(ref.read(videoPlaybackProvider));
      debugPrint('Ошибка инициализации видео $i ($startUrl): $e');
      if (mounted) {
        setState(() => _videoInitFailed[i] = true);
      }
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
    if (index < 0 || index >= _reels.length) return;
    final pref = ref.read(videoPlaybackProvider);
    final urls = <String?>[
      if (index > 0) _reels[index - 1].reelVideoSources.prefetchUrl(pref),
      if (index + 1 < _reels.length)
        _reels[index + 1].reelVideoSources.prefetchUrl(pref),
      if (index + 2 < _reels.length)
        _reels[index + 2].reelVideoSources.prefetchUrl(pref),
    ];
    prefetchReelVideoUrls(urls);
  }

  /// Инициализация соседних контроллеров после старта текущего (без борьбы за сеть).
  void _scheduleNeighborControllers(int index) {
    if (!mounted || !_canPlayVideos) return;
    final retain = _controllerRetainDistance;

    void schedule(int neighbor, Duration delay) {
      if (neighbor < 0 || neighbor >= _reels.length) return;
      if (_videoControllers.containsKey(neighbor)) return;
      unawaited(
        Future<void>.delayed(delay, () async {
          if (!mounted || !_canPlayVideos) return;
          if (_videoControllers.containsKey(neighbor)) return;
          if ((neighbor - _currentIndex).abs() > retain) return;
          await _initSingleVideo(neighbor);
        }),
      );
    }

    schedule(index + 1, const Duration(milliseconds: 180));
    schedule(index - 1, const Duration(milliseconds: 420));
    schedule(index + 2, const Duration(milliseconds: 760));
  }

  void _retainMatchingControllerOnRefresh(List<PostModel> nextReels) {
    final kept = <int, VideoPlayerController>{};
    final cur = _currentIndex;
    final pref = ref.read(videoPlaybackProvider);
    if (cur >= 0 &&
        cur < _reels.length &&
        cur < nextReels.length &&
        _reels[cur].id == nextReels[cur].id &&
        _reels[cur].videoUrlFor(pref) == nextReels[cur].videoUrlFor(pref)) {
      final c = _videoControllers[cur];
      if (c != null) kept[cur] = c;
    }
    for (final entry in _videoControllers.entries) {
      if (!kept.containsKey(entry.key)) {
        entry.value.dispose();
      }
    }
    _videoControllers
      ..clear()
      ..addAll(kept);
    _isPaused.removeWhere((i, _) => !kept.containsKey(i));
    _videoInitFailed.removeWhere((i, _) => !kept.containsKey(i));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _followingOnly = widget.externalFollowingOnly;
    final cached = FeedApiCache.peek(_cacheVariant);
    if (cached.isNotEmpty) {
      _reels = cached;
      _servingFromCache = true;
    }
    _realtimeSub = UserRealtimeService.instance.events.listen((event) {
      if (!mounted || event.event != 'sync') return;
      if (!widget.isTabVisible || _isLoading) return;
      unawaited(_loadReels(refresh: true));
    });
    _syncEmbeddedShellNav();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLoadIfNeeded());
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
    if (mounted && widget.isTabVisible) {
      _playReelAt(_currentIndex);
    }
  }

  void _syncEmbeddedShellNav() {
    if (!widget.hideScaffold) return;
    syncRootShellBottomNavForReels(
      embeddedInShell: true,
      tabVisible: widget.isTabVisible,
    );
  }

  @override
  void didUpdateWidget(ReelsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTabVisible != oldWidget.isTabVisible) {
      _syncEmbeddedShellNav();
    }
    if (widget.externalFollowingOnly != oldWidget.externalFollowingOnly &&
        widget.externalFollowingOnly != _followingOnly) {
      _followingOnly = widget.externalFollowingOnly;
      if (widget.isTabVisible) {
        _loadReels(refresh: true);
      }
    }
    if (widget.isTabVisible && !oldWidget.isTabVisible) {
      _startLoadIfNeeded();
      if (_canPlayVideos && _reels.isNotEmpty) {
        _initializeVideos(
          _currentIndex,
          math.min(_initialVideoPreloadCount, _reels.length - _currentIndex),
          priorityIndex: _currentIndex,
        );
        final c = _videoControllers[_currentIndex];
        if (c != null) _playReelAt(_currentIndex);
      }
    } else if (!widget.isTabVisible && oldWidget.isTabVisible) {
      _pauseAllVideos();
      _disposeAllControllers();
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
    _realtimeSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _loadReels({bool refresh = false}) async {
    if (_isLoading && !refresh) return;

    final requestId = ++_loadGeneration;

    if (refresh) {
      var cached = FeedApiCache.peek(_cacheVariant);
      if (cached.isEmpty) {
        cached = await FeedApiCache.load(_cacheVariant);
      }
      if (!mounted || requestId != _loadGeneration) return;
      if (cached.isNotEmpty) {
        setState(() {
          _reels = cached;
          _nextCursor = null;
          _hasMore = true;
          _isLoading = true;
          _lastLoadError = null;
          _servingFromCache = true;
          _cacheLoadError = null;
        });
        unawaited(
          _initializeVideos(
            _currentIndex,
            math.min(_initialVideoPreloadCount, cached.length - _currentIndex),
            priorityIndex: _currentIndex,
          ),
        );
        if (_currentIndex < cached.length) {
          _startReelExposure(_currentIndex);
        }
      } else {
        setState(() {
          _isLoading = true;
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
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    if (refresh && !feedDeviceOnline()) {
      if (_reels.isNotEmpty) {
        if (mounted && requestId == _loadGeneration) {
          setState(() {
            _isLoading = false;
            _cacheLoadError = 'offline';
          });
        }
        return;
      }
      final cached = await FeedApiCache.load(_cacheVariant);
      if (!mounted || requestId != _loadGeneration) return;
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
        unawaited(
          _initializeVideos(
            _currentIndex,
            math.min(_initialVideoPreloadCount, cached.length - _currentIndex),
            priorityIndex: _currentIndex,
          ),
        );
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

      if (!mounted || requestId != _loadGeneration) return;
      final prevLen = _reels.length;
      final fetched =
          refresh ? response.items : <PostModel>[..._reels, ...response.items];
      final nextReels =
          refresh ? _mergePreservingRecentLikes(fetched) : fetched;
      if (refresh) {
        _retainMatchingControllerOnRefresh(nextReels);
      }
      setState(() {
        _reels = nextReels;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
      });
      unawaited(FeedApiCache.save(_cacheVariant, nextReels));

      if (_reels.isNotEmpty) {
        if (refresh) {
          unawaited(
            _initializeVideos(
              _currentIndex,
              math.min(
                _initialVideoPreloadCount,
                _reels.length - _currentIndex,
              ),
              priorityIndex: _currentIndex,
            ),
          );
          _startReelExposure(_currentIndex);
        } else {
          final added = nextReels.length - prevLen;
          if (added > 0) {
            unawaited(
              _initializeVideos(
                prevLen,
                math.min(2, added),
                priorityIndex: _currentIndex,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted && requestId == _loadGeneration) {
        if (FeedLoadHelper.isSessionError(e)) {
          await FeedLoadHelper.clearSessionIfExpired(e);
          return;
        }
        final cached = await FeedApiCache.load(_cacheVariant);
        if (!mounted || requestId != _loadGeneration) return;
        if (cached.isNotEmpty) {
          setState(() {
            _reels = _mergePreservingRecentLikes(cached);
            _nextCursor = null;
            _hasMore = false;
            _lastLoadError = null;
            _servingFromCache = true;
            _cacheLoadError = e;
          });
          unawaited(
            _initializeVideos(
              _currentIndex,
              math.min(
                _initialVideoPreloadCount,
                cached.length - _currentIndex,
              ),
              priorityIndex: _currentIndex,
            ),
          );
          _startReelExposure(_currentIndex);
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
      if (mounted && requestId == _loadGeneration) {
        setState(() => _isLoading = false);
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
      _playReelAt(index);
    } else {
      unawaited(
        _initializeVideos(index, 1, priorityIndex: index).then((_) {
          if (mounted) _playReelAt(index);
        }),
      );
    }

    // Загружаем больше, если приближаемся к концу
    if (index >= _reels.length - 3 && _hasMore && !_isLoading) {
      _loadReels();
    }

    _prefetchAdjacentReelFiles(index);
    if (_lookaheadVideoPreloadCount > 0) {
      _scheduleNeighborControllers(index);
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
    final retain = _controllerRetainDistance;
    final stale = _videoControllers.keys
        .where((i) => (i - _currentIndex).abs() > retain)
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
              onLike: () => _toggleLike(reel.id),
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
              onQualityChanged: () => _reloadReelVideo(index),
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

  Future<void> _toggleLike(int postId) async {
    if (_likeBusy.contains(postId)) return;
    final index = _reels.indexWhere((r) => r.id == postId);
    if (index == -1) return;

    final wasLiked = _reels[index].isLiked;
    _likeBusy.add(postId);
    _likeTouchedAt[postId] = DateTime.now();

    setState(() {
      _reels[index] = _reels[index].copyWith(
        isLiked: !wasLiked,
        likesCount: _reels[index].likesCount + (wasLiked ? -1 : 1),
      );
    });

    try {
      final response = wasLiked
          ? await LikeService.unlikePost(postId)
          : await LikeService.likePost(postId);
      if (!mounted) return;
      final i = _reels.indexWhere((r) => r.id == postId);
      if (i != -1) {
        setState(() {
          _reels[i] = _reels[i].copyWith(
            likesCount: response.likesCount,
            isLiked: response.liked,
          );
        });
        unawaited(FeedApiCache.save(_cacheVariant, _reels));
      }
    } catch (e) {
      if (!mounted) return;
      final i = _reels.indexWhere((r) => r.id == postId);
      if (i != -1) {
        setState(() {
          _reels[i] = _reels[i].copyWith(
            isLiked: wasLiked,
            likesCount: _reels[i].likesCount + (wasLiked ? 1 : -1),
          );
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
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

  Future<void> _shareReel(PostModel reel) async {
    await ShareActionSheet.showForReel(
      context,
      reel: reel,
      onRepostToWall: () => _toggleRepost(reel),
    );
  }
}

class ReelCard extends ConsumerStatefulWidget {
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
  final VoidCallback? onQualityChanged;

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
    this.onQualityChanged,
  });

  @override
  ConsumerState<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends ConsumerState<ReelCard>
    with SingleTickerProviderStateMixin {
  DateTime? _lastTap;
  Timer? _singleTapTimer;
  bool _showLikeAnimation = false;
  late AnimationController _likeAnimationController;
  late Animation<double> _likeScaleAnimation;
  late Animation<double> _likeOpacityAnimation;
  final List<TapGestureRecognizer> _descriptionRecognizers = [];

  static const double _igActionGap = 14;
  static const double _igRightInset = 12;
  static const double _igRailWidth = 50;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

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
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _clearDescriptionRecognizers();
    _likeAnimationController.dispose();
    super.dispose();
  }

  void _clearDescriptionRecognizers() {
    for (final r in _descriptionRecognizers) {
      r.dispose();
    }
    _descriptionRecognizers.clear();
  }

  void _showMoreMenu() {
    final scheme = Theme.of(context).colorScheme;
    final currentQuality = ref.watch(videoPlaybackProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Качество видео',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            ...VideoQualityPreference.values.map((pref) {
              final selected = currentQuality == pref;
              return ListTile(
                dense: true,
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                title: Text(pref.labelRu),
                subtitle: Text(pref.subtitleRu),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (pref == ref.read(videoPlaybackProvider)) return;
                  await ref
                      .read(videoPlaybackProvider.notifier)
                      .setPreference(pref);
                  widget.onQualityChanged?.call();
                },
              );
            }),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                (widget.reel.isSaved ?? false)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              title: Text(
                (widget.reel.isSaved ?? false)
                    ? 'Убрать из сохранённых'
                    : 'Сохранить',
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

  Future<void> _toggleMute() async {
    widget.onMutePreferenceChanged(!widget.isMuted);
  }

  void _handleSingleTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _doubleTapWindow) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _handleDoubleTap();
      _lastTap = null;
      return;
    }
    _lastTap = now;
    _singleTapTimer?.cancel();
    _singleTapTimer = Timer(_doubleTapWindow, _togglePlayback);
  }

  Future<void> _togglePlayback() async {
    _singleTapTimer = null;
    _lastTap = null;
    if (widget.videoController == null) return;
    final paused =
        await VideoPlayerHelper.toggleOrStart(widget.videoController!);
    if (mounted) widget.onPauseToggle(paused);
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
          if (widget.isPaused)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.15),
                ),
              ),
            ),
          if (widget.isPaused && widget.videoController != null)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    color: widget.reel.isLiked
                        ? const Color(0xFFFF3040)
                        : Colors.white,
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
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.34),
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
          if (widget.videoController != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ReelPlaybackProgress(controller: widget.videoController!),
            ),
        ],
      ),
    );
  }

  Widget _buildDescription(String description) {
    _clearDescriptionRecognizers();
    final words = description.split(' ');
    final accent = Theme.of(context).colorScheme.primary;
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
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: r,
            );
          }
          final emojiMatch = RegExp(r'^\[\[e:(\d+)\]\]$').firstMatch(word);
          if (emojiMatch != null) {
            final id = int.tryParse(emojiMatch.group(1) ?? '') ?? 0;
            if (id > 0) {
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: CustomEmojiView(id: id, size: 18),
                ),
              );
            }
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
              style: TextStyle(
                color: accent,
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

/// Прогресс воспроизведения без перерисовки всей [ReelCard].
class _ReelPlaybackProgress extends StatelessWidget {
  const _ReelPlaybackProgress({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.value;
        if (!value.isInitialized) return const SizedBox.shrink();
        final durationMs = value.duration.inMilliseconds;
        if (durationMs <= 0) return const SizedBox.shrink();
        final progress =
            (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
        return SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
      },
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
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: color ?? Colors.white,
                size: 24,
              ),
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
