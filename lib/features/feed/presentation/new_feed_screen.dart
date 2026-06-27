// Новый экран ленты с постами из API
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/feed_connectivity.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../models/post_model.dart';
import '../../../models/post_types.dart';
import '../../../services/feed_api_cache.dart';
import '../../../services/feed_analytics_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/user_realtime_service.dart';
import 'new_post_card.dart';
import '../../../app/app_router.dart';
import '../../../widgets/post_card_skeleton.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../content/create_content_actions.dart';
import '../../navigation/application/feed_scroll_chrome.dart';

class NewFeedScreen extends ConsumerStatefulWidget {
  const NewFeedScreen({
    super.key,
    this.hideScaffold = false,

    /// Тип ленты с родителя ([MainFeedScreen]); если null — экран сам хранит фильтр (полный Scaffold).
    this.externalFeedType,
    this.externalSortMode,
    this.deferLoad = false,
  });

  /// Если true, не показывать Scaffold и AppBar (для использования внутри табов)
  final bool hideScaffold;

  /// См. [externalFeedType].
  final String? externalFeedType;

  /// Сортировка с родителя; если null — personalized.
  final FeedSortMode? externalSortMode;

  /// Не загружать ленту до первого показа таба (web).
  final bool deferLoad;

  @override
  ConsumerState<NewFeedScreen> createState() => _NewFeedScreenState();
}

class _NewFeedScreenState extends ConsumerState<NewFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  String _feedType = 'all';
  FeedSortMode _sortMode = FeedSortMode.personalized;
  bool _pendingLoadMore = false;
  bool _loadKickoff = false;
  int _loadGeneration = 0;

  /// Последняя ошибка загрузки (таймаут / API недоступен) — не путать с «в БД нет постов».
  String? _lastLoadError;

  /// Посты с диска (офлайн / ошибка сети).
  bool _servingFromCache = false;
  Object? _cacheLoadError;
  StreamSubscription<UserRealtimeEvent>? _realtimeSub;

  String _cacheVariant([String? feedType, FeedSortMode? sortMode]) =>
      'rec_${feedType ?? _feedType}_${(sortMode ?? _sortMode).value}';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _feedType = widget.externalFeedType ?? 'all';
    _sortMode = widget.externalSortMode ?? FeedSortMode.personalized;
    _scrollController.addListener(_onScroll);
    final cached = FeedApiCache.peek(_cacheVariant());
    if (cached.isNotEmpty) {
      _posts = cached;
      _servingFromCache = true;
      _loadKickoff = true;
    }
    _realtimeSub = UserRealtimeService.instance.events.listen((event) {
      if (!mounted || event.event != 'sync') return;
      if (_isLoading) return;
      unawaited(_loadFeed(refresh: true));
    });
    if (!widget.deferLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _loadKickoff = true);
        _loadFeed(refresh: true);
      });
    }
  }

  @override
  void didUpdateWidget(NewFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deferLoad != oldWidget.deferLoad &&
        !widget.deferLoad &&
        !_loadKickoff) {
      setState(() => _loadKickoff = true);
      _loadFeed(refresh: true);
    }
    final ext = widget.externalFeedType;
    if (ext != null && ext != oldWidget.externalFeedType) {
      _feedType = ext;
      _loadFeed(refresh: true);
    }
    final sort = widget.externalSortMode;
    if (sort != null && sort != oldWidget.externalSortMode) {
      _sortMode = sort;
      _loadFeed(refresh: true);
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasViewportDimension || pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadFeed({bool refresh = false}) async {
    if (_isLoading && !refresh) {
      if (!refresh) _pendingLoadMore = true;
      return;
    }

    final requestId = ++_loadGeneration;
    final requestedFeedType = _feedType;
    final requestedSortMode = _sortMode;
    final requestedCacheVariant =
        _cacheVariant(requestedFeedType, requestedSortMode);

    if (refresh) {
      final cached = await FeedApiCache.load(requestedCacheVariant);
      if (!mounted) return;
      if (requestId != _loadGeneration) return;
      if (cached.isNotEmpty) {
        setState(() {
          _posts = cached;
          _nextCursor = null;
          _hasMore = true;
          _isLoading = true;
          _lastLoadError = null;
          _servingFromCache = true;
          _cacheLoadError = null;
        });
      } else {
        setState(() {
          _isLoading = true;
          _posts = [];
          _nextCursor = null;
          _hasMore = true;
          _lastLoadError = null;
          _servingFromCache = false;
          _cacheLoadError = null;
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    if (refresh && !feedDeviceOnline()) {
      if (_posts.isNotEmpty) {
        if (mounted && requestId == _loadGeneration) {
          setState(() {
            _isLoading = false;
            _cacheLoadError = 'offline';
          });
        }
        return;
      }
      final cached = await FeedApiCache.load(requestedCacheVariant);
      if (!mounted) return;
      if (requestId != _loadGeneration) return;
      if (cached.isNotEmpty) {
        setState(() {
          _posts = cached;
          _nextCursor = null;
          _hasMore = false;
          _lastLoadError = null;
          _servingFromCache = true;
          _cacheLoadError = 'offline';
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final response = await FeedService.getFeed(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
        feedType: requestedFeedType,
        sortMode: requestedSortMode,
      );

      if (!mounted) return;
      if (requestId != _loadGeneration) return;
      final nextPosts =
          refresh ? response.items : <PostModel>[..._posts, ...response.items];
      setState(() {
        _posts = nextPosts;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
      });
      await FeedApiCache.save(requestedCacheVariant, nextPosts);
    } catch (e) {
      if (mounted) {
        if (requestId != _loadGeneration) return;
        if (FeedLoadHelper.isSessionError(e)) {
          await FeedLoadHelper.clearSessionIfExpired(e);
          return;
        }
        final cached = await FeedApiCache.load(requestedCacheVariant);
        if (!mounted) return;
        if (requestId != _loadGeneration) return;
        if (cached.isNotEmpty) {
          setState(() {
            _posts = cached;
            _nextCursor = null;
            _hasMore = false;
            _lastLoadError = null;
            _servingFromCache = true;
            _cacheLoadError = e;
          });
        } else {
          final short = FeedLoadHelper.feedLoadErrorMessage(e);
          setState(() {
            _lastLoadError = short;
          });
        }
      }
    } finally {
      final stillMounted = mounted;
      if (stillMounted && requestId == _loadGeneration) {
        setState(() => _isLoading = false);
      }
      final runPending = _pendingLoadMore;
      _pendingLoadMore = false;
      if (runPending &&
          _hasMore &&
          stillMounted &&
          requestId == _loadGeneration) {
        await _loadFeed(refresh: false);
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadFeed(refresh: false);
  }

  double _listBottomPadding(BuildContext context, bool chromeHidden) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    if (chromeHidden) return safeBottom + 12;
    return floatingBottomPadding(context);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final showInitialPlaceholder =
        !_loadKickoff && _posts.isEmpty && !_isLoading;
    final emptyOrLoading = showInitialPlaceholder ||
            (_posts.isEmpty && _isLoading)
        ? const PostListSkeletonLoader(itemCount: 5)
        : _posts.isEmpty
            ? ValueListenableBuilder<bool>(
                valueListenable: feedScrollChromeHidden,
                builder: (context, chromeHidden, _) {
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.only(
                          bottom: _listBottomPadding(context, chromeHidden),
                        ),
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: AppEmptyState(
                            icon: Icons.dynamic_feed_outlined,
                            title: _lastLoadError != null
                                ? 'Не удалось загрузить ленту'
                                : 'Пока нет постов',
                            subtitle: _lastLoadError ??
                                'Обновите ленту или смените фильтр в меню выше.',
                            action: _lastLoadError != null
                                ? FilledButton.icon(
                                    onPressed: () => _loadFeed(refresh: true),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Повторить'),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              )
            : ValueListenableBuilder<bool>(
                valueListenable: feedScrollChromeHidden,
                builder: (context, chromeHidden, _) {
                  return ListView.builder(
                    controller: _scrollController,
                    cacheExtent: kIsWeb ? 200 : 250,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: EdgeInsets.only(
                        bottom: _listBottomPadding(context, chromeHidden)),
                    itemCount: (_servingFromCache ? 1 : 0) +
                        _posts.length +
                        (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      final banner = _servingFromCache ? 1 : 0;
                      if (banner == 1 && index == 0) {
                        final scheme = Theme.of(context).colorScheme;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Material(
                            color: scheme.secondaryContainer
                                .withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.offline_pin_outlined,
                                    size: 20,
                                    color: scheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      FeedLoadHelper.cacheBannerMessage(
                                        _cacheLoadError ?? '',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSecondaryContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final postIndex = index - banner;
                      if (postIndex >= 0 && postIndex < _posts.length) {
                        final post = _posts[postIndex];
                        return FeedExposureTracker(
                          post: post,
                          feedSurface: 'recommendations_$_feedType',
                          position: postIndex,
                          child: NewPostCard(
                            key: ValueKey('recommendations_post_${post.id}'),
                            post: post,
                            onCommentTap: () {
                              FeedAnalyticsService.openDetail(
                                post,
                                source: 'recommendations_$_feedType',
                                target: 'comments',
                              );
                              return context
                                  .push(PostCommentsRoute.pathFor(post.id));
                            },
                            onPostDeleted: () {
                              setState(() {
                                _posts.removeWhere((p) => p.id == post.id);
                              });
                            },
                            onAuthorTap: () {
                              if (post.repostedBy != null) {
                                context.push(ProfileRoute.withUserId(
                                    post.repostedBy!.id));
                              } else if (post.communityId != null) {
                                context.push(ChannelDetailRoute.pathFor(
                                    post.communityId!));
                              } else {
                                context
                                    .push(ProfileRoute.withUserId(post.userId));
                              }
                            },
                          ),
                        );
                      }
                      if (_hasMore && index == banner + _posts.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              );

    final bodyContent = FeedScrollChromeListener(
      enabled: widget.hideScaffold,
      child: RefreshIndicator(
        onRefresh: () => _loadFeed(refresh: true),
        child: emptyOrLoading,
      ),
    );

    if (widget.hideScaffold) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Лента'),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_library),
            onPressed: () => context.push(ReelsRoute.path),
            tooltip: 'Рилсы',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(SearchRoute.path),
            tooltip: 'Поиск',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _feedType = value;
              });
              _loadFeed(refresh: true);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Text(
                  'Все',
                  style: TextStyle(
                      fontWeight: _feedType == 'all' ? FontWeight.bold : null),
                ),
              ),
              PopupMenuItem(
                value: 'photos',
                child: Text(
                  'Фото',
                  style: TextStyle(
                      fontWeight:
                          _feedType == 'photos' ? FontWeight.bold : null),
                ),
              ),
              PopupMenuItem(
                value: 'recipes',
                child: Text(
                  'Рецепты',
                  style: TextStyle(
                      fontWeight:
                          _feedType == 'recipes' ? FontWeight.bold : null),
                ),
              ),
              PopupMenuItem(
                value: 'reels',
                child: Text(
                  'Рилсы',
                  style: TextStyle(
                      fontWeight:
                          _feedType == 'reels' ? FontWeight.bold : null),
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
      body: bodyContent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateContentSheet(context, ref: ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}
