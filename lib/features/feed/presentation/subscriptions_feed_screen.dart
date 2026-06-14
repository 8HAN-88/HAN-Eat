// Экран ленты подписок с постами от подписанных пользователей
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
import 'new_post_card.dart';
import '../../../app/app_router.dart';
import '../../../widgets/post_card_skeleton.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../core/layout/floating_bottom_padding.dart';
import '../../navigation/application/feed_scroll_chrome.dart';

/// Лента постов от подписанных пользователей
class SubscriptionsFeedScreen extends ConsumerStatefulWidget {
  const SubscriptionsFeedScreen({
    super.key,
    this.externalFeedType,
    this.externalSortMode,
    this.deferLoad = false,
  });

  /// Тип контента с родителя ([MainFeedScreen]).
  final String? externalFeedType;

  /// Сортировка с родителя; по умолчанию — сначала новые.
  final FeedSortMode? externalSortMode;

  /// Не загружать ленту до первого показа таба (web).
  final bool deferLoad;

  @override
  ConsumerState<SubscriptionsFeedScreen> createState() =>
      _SubscriptionsFeedScreenState();
}

class _SubscriptionsFeedScreenState
    extends ConsumerState<SubscriptionsFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  bool _pendingLoadMore = false;
  bool _loadKickoff = false;
  String? _lastLoadError;
  bool _servingFromCache = false;
  Object? _cacheLoadError;

  String _feedType = 'all';
  FeedSortMode _sortMode = FeedSortMode.recent;

  String get _cacheVariant => 'following_${_feedType}_${_sortMode.value}';

  @override
  bool get wantKeepAlive => !kIsWeb;

  @override
  void initState() {
    super.initState();
    _feedType = widget.externalFeedType ?? 'all';
    _sortMode = widget.externalSortMode ?? FeedSortMode.recent;
    _scrollController.addListener(_onScroll);
    if (!widget.deferLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _loadKickoff = true);
        _loadFeed(refresh: true);
      });
    }
  }

  @override
  void didUpdateWidget(SubscriptionsFeedScreen oldWidget) {
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

    // Проверяем авторизацию
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
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
      final cached = await FeedApiCache.load(_cacheVariant);
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
        followingOnly: true,
        sortMode: _sortMode,
      );

      if (!mounted) return;
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
      await FeedApiCache.save(_cacheVariant, nextPosts);
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
      if (runPending &&
          _hasMore &&
          stillMounted &&
          AuthService.instance.currentUser != null) {
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
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      return AppEmptyState(
        icon: Icons.login_rounded,
        title: 'Войдите в аккаунт',
        subtitle: 'Чтобы видеть посты от людей, на которых вы подписаны.',
      );
    }

    if (_posts.isEmpty && !_isLoading && !_loadKickoff) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty && !_isLoading) {
      return FeedScrollChromeListener(
        child: RefreshIndicator(
        onRefresh: () => _loadFeed(refresh: true),
        child: ValueListenableBuilder<bool>(
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
                  icon: _lastLoadError != null
                      ? Icons.cloud_off_outlined
                      : Icons.subscriptions_outlined,
                  title: _lastLoadError != null
                      ? 'Не удалось загрузить ленту'
                      : 'Подписки',
                  subtitle: _lastLoadError ??
                      'Подпишитесь на авторов, чтобы видеть их посты здесь.',
                  action: _lastLoadError != null
                      ? FilledButton.icon(
                          onPressed: () => _loadFeed(refresh: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить'),
                        )
                      : FilledButton.icon(
                          onPressed: () => context.push(SearchRoute.path),
                          icon: const Icon(Icons.search),
                          label: const Text('Найти авторов'),
                        ),
                ),
              ),
            ),
          ],
        );
          },
        ),
      ),
      );
    }

    return FeedScrollChromeListener(
      child: RefreshIndicator(
      onRefresh: () => _loadFeed(refresh: true),
      child: _posts.isEmpty && _isLoading
          ? const PostListSkeletonLoader(itemCount: 5)
          : ValueListenableBuilder<bool>(
              valueListenable: feedScrollChromeHidden,
              builder: (context, chromeHidden, _) {
                return ListView.builder(
              controller: _scrollController,
              cacheExtent: kIsWeb ? 200 : 250,
              padding: EdgeInsets.only(
                bottom: _listBottomPadding(context, chromeHidden),
              ),
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
                      color: scheme.secondaryContainer.withValues(alpha: 0.95),
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
                    feedSurface: 'following',
                    position: postIndex,
                    child: NewPostCard(
                      post: post,
                      onCommentTap: () {
                        FeedAnalyticsService.openDetail(
                          post,
                          source: 'following',
                          target: 'comments',
                        );
                        return context.push(PostCommentsRoute.pathFor(post.id));
                      },
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
            ),
    ),
    );
  }
}
