// Новый экран ленты с постами из API
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/feed_connectivity.dart';
import '../../../core/network/feed_load_helper.dart';
import '../../../models/post_model.dart';
import '../../../services/feed_api_cache.dart';
import '../../../services/feed_service.dart';
import 'new_post_card.dart';
import '../../../app/app_router.dart';
import '../../../widgets/post_card_skeleton.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../content/create_content_actions.dart';

class NewFeedScreen extends ConsumerStatefulWidget {
  const NewFeedScreen({
    super.key,
    this.hideScaffold = false,

    /// Тип ленты с родителя ([MainFeedScreen]); если null — экран сам хранит фильтр (полный Scaffold).
    this.externalFeedType,
  });

  /// Если true, не показывать Scaffold и AppBar (для использования внутри табов)
  final bool hideScaffold;

  /// См. [externalFeedType].
  final String? externalFeedType;

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
  bool _pendingLoadMore = false;
  bool _loadKickoff = false;
  /// Последняя ошибка загрузки (таймаут / API недоступен) — не путать с «в БД нет постов».
  String? _lastLoadError;

  /// Посты с диска (офлайн / ошибка сети).
  bool _servingFromCache = false;
  Object? _cacheLoadError;

  String _cacheVariant() => 'rec_$_feedType';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _feedType = widget.externalFeedType ?? 'all';
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _loadKickoff = true);
      _loadFeed(refresh: true);
    });
  }

  @override
  void didUpdateWidget(NewFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ext = widget.externalFeedType;
    if (ext != null && ext != oldWidget.externalFeedType && ext != _feedType) {
      _feedType = ext;
      _loadFeed(refresh: true);
    }
  }

  @override
  void dispose() {
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
    if (_isLoading) {
      if (!refresh) _pendingLoadMore = true;
      return;
    }

    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts = [];
        _nextCursor = null;
        _hasMore = true;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
      }
    });

    if (refresh && !feedDeviceOnline()) {
      final cached = await FeedApiCache.load(_cacheVariant());
      if (!mounted) return;
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
        feedType: _feedType,
      );

      if (!mounted) return;
      final nextPosts = refresh
          ? response.items
          : <PostModel>[..._posts, ...response.items];
      setState(() {
        _posts = nextPosts;
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
        _lastLoadError = null;
        _servingFromCache = false;
        _cacheLoadError = null;
      });
      await FeedApiCache.save(_cacheVariant(), nextPosts);
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
        final cached = await FeedApiCache.load(_cacheVariant());
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
          setState(() => _lastLoadError = short);
        }
      }
    } finally {
      final stillMounted = mounted;
      if (stillMounted) {
        setState(() => _isLoading = false);
      }
      final runPending = _pendingLoadMore;
      _pendingLoadMore = false;
      if (runPending && _hasMore && stillMounted) {
        await _loadFeed(refresh: false);
      }
    }
  }

  Future<void> _loadMore() async {
    await _loadFeed(refresh: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final showInitialPlaceholder =
        !_loadKickoff && _posts.isEmpty && !_isLoading;
    final emptyOrLoading =
        showInitialPlaceholder || (_posts.isEmpty && _isLoading)
            ? const PostListSkeletonLoader(itemCount: 5)
            : _posts.isEmpty
                ? CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
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
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        EdgeInsets.only(bottom: floatingBottomPadding(context)),
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
                        return NewPostCard(
                          post: post,
                          onCommentTap: () =>
                              context.push(PostCommentsRoute.pathFor(post.id)),
                          onPostDeleted: () {
                            setState(() {
                              _posts.removeWhere((p) => p.id == post.id);
                            });
                          },
                          onAuthorTap: () {
                            if (post.repostedBy != null) {
                              context.push(
                                  ProfileRoute.withUserId(post.repostedBy!.id));
                            } else if (post.communityId != null) {
                              context.push(
                                  ChannelDetailRoute.pathFor(post.communityId!));
                            } else {
                              context.push(ProfileRoute.withUserId(post.userId));
                            }
                          },
                        );
                      }
                      if (_hasMore &&
                          index == banner + _posts.length) {
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

    final bodyContent = RefreshIndicator(
      onRefresh: () => _loadFeed(refresh: true),
      child: emptyOrLoading,
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
