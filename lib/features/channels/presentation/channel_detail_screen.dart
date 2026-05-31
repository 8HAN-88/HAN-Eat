// Экран детального просмотра канала с лентой постов (согласно UI-прототипу)
import 'dart:async';
import '../../../utils/api_error_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../models/post_model.dart';
import '../../../core/share/system_share.dart';
import '../../../services/server_config.dart';
import '../../../services/share_link_service.dart';
import '../../../app/app_router.dart';
import '../application/channels_list_refresh_provider.dart';
import 'channel_settings_bottom_sheet.dart';
import 'channel_detail_screen_tabs.dart';
import 'channel_search_screen.dart';
import 'channel_create_content_sheet.dart';

import 'channel_post_card.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../core/theme/app_card_decorations.dart';

/// Получить URL для сетки «Медиа» / галереи: без подмены на `_medium` (иначе мыло на Retina).
String imageUrlForChannelMediaGrid(String url) {
  final u = url.trim();
  if (u.isEmpty) return u;
  return ServerConfig.resolveMediaUrl(u);
}

/// Размер декода для ячейки сетки «Медиа» (логическая ширина × DPR × запас).
/// Слишком маленький decode → апскейл на экране и «мыло»; запас ~2× даёт чёткую картинку.
int channelMediaThumbDecodeSize(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final width = MediaQuery.sizeOf(context).width;
  const gridPadding = 16.0;
  const crossAxisCount = 3;
  const spacingTotal = 8.0;
  final cellLogical = (width - gridPadding - spacingTotal) / crossAxisCount;
  final px = (cellLogical * dpr * 2.0).ceil();
  return px.clamp(512, 4096);
}

class ChannelDetailScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelDetailScreen({
    super.key,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen> {
  ChannelDetail? _channel;
  bool _isLoading = true;
  Object? _channelLoadError;
  bool _isJoining = false;
  final GlobalKey<ChannelPostsListState> _postsListKey =
      GlobalKey<ChannelPostsListState>();

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      if (forceRefresh) {
        _channelLoadError = null;
      }
    });

    try {
      // Сначала пытаемся загрузить из кэша (быстро)
      if (!forceRefresh) {
        try {
          final cachedChannel = await ChannelCacheService.getChannel(
            widget.channelId,
            forceRefresh: false,
          );
          if (mounted) {
            setState(() {
              _channel = cachedChannel;
              _isLoading = false;
            });
            // Загружаем свежие данные в фоне
            unawaited(_refreshChannelSilently());
            return;
          }
        } catch (e) {
          debugPrint('Cache miss, loading from server: $e');
        }
      }

      // Загружаем с сервера
      final channel = await ChannelCacheService.getChannel(
        widget.channelId,
        forceRefresh: forceRefresh,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут загрузки канала');
        },
      );

      if (mounted) {
        setState(() {
          _channel = channel;
          _channelLoadError = null;
        });
      }
    } on ChannelNotFoundException {
      await _handleChannelGone();
    } catch (e) {
      debugPrint('Ошибка загрузки канала: $e');
      if (mounted) {
        setState(() => _channelLoadError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshChannelSilently() async {
    try {
      final channel = await ChannelCacheService.getChannel(
        widget.channelId,
        forceRefresh: true,
      );
      if (mounted) setState(() => _channel = channel);
    } on ChannelNotFoundException {
      await _handleChannelGone();
    } catch (e) {
      debugPrint('Фоновое обновление канала: $e');
    }
  }

  Future<void> _handleChannelGone() async {
    await ChannelCacheService.invalidateChannelCache(widget.channelId);
    ref.read(channelsMainListRefreshProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _channel = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Канал удалён или больше не доступен'),
        duration: Duration(seconds: 3),
      ),
    );
    if (context.canPop()) {
      context.pop();
    }
  }

  Future<void> _openCreatePost() async {
    final result = await context.push(
      ChannelDetailRoute.createPost(widget.channelId),
    );
    if (result is PostModel) {
      _postsListKey.currentState?.addPost(result);
    } else if (result == true) {
      _postsListKey.currentState?.refreshPosts();
    }
  }

  Future<void> _toggleSubscribe() async {
    if (_channel == null || _isJoining) return;

    setState(() => _isJoining = true);

    try {
      if (_channel!.isMember) {
        await ChannelService.leaveChannel(widget.channelId);
      } else {
        await ChannelService.joinChannel(widget.channelId);
      }

      // Перезагружаем канал для обновления статуса
      await _loadChannel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_channel == null) {
      if (_channelLoadError != null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Канал')),
          body: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Не удалось загрузить канал',
            subtitle: userVisibleError(
              _channelLoadError!,
              fallback: 'Проверьте сеть',
            ),
            action: FilledButton(
              onPressed: () => _loadChannel(forceRefresh: true),
              child: const Text('Повторить'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const AppEmptyState(
          icon: Icons.group_off_outlined,
          title: 'Канал не найден',
          subtitle: 'Возможно, он удалён или у вас нет доступа',
        ),
      );
    }

    final c = _channel!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(ChannelsListRoute.path);
            }
          },
        ),
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openChannelInfoPage,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage:
                      c.avatarUrl != null && c.avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(c.avatarUrl!)
                          : null,
                  child: c.avatarUrl == null || c.avatarUrl!.isEmpty
                      ? Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${c.membersCount} подписчиков',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            icon: const Icon(Icons.search),
            onPressed: _openSearchFullscreen,
          ),
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.more_vert),
            onPressed: _showChannelSettings,
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: AppGradientBackground(
        child: c.canViewPosts
            ? ChannelPostsList(
                key: _postsListKey,
                channelId: widget.channelId,
                channel: c,
                postType: null,
              )
            : _PrivateChannelPostsLocked(channel: c),
      ),
      floatingActionButton: (c.isAdmin || c.isOwner)
          ? FloatingActionButton(
              onPressed: () => showChannelCreateContentSheet(
                context,
                channelId: widget.channelId,
                channelName: c.name,
              ),
              tooltip: 'Создать',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _openChannelInfoPage() {
    if (_channel == null) return;
    context
        .push<void>(
      ChannelDetailRoute.info(
        widget.channelId,
        channelName: _channel!.name,
      ),
    )
        .then((_) {
      if (mounted) _loadChannel(forceRefresh: true);
    });
  }

  void _openSearchFullscreen() {
    if (_channel == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => ChannelSearchScreen(
          channelId: widget.channelId,
          initialQuery: '',
          channel: _channel!,
        ),
      ),
    );
  }

  void _showChannelSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      showDragHandle: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 320),
        reverseDuration: Duration(milliseconds: 260),
      ),
      builder: (context) => ChannelSettingsBottomSheet(
        channel: _channel!,
        channelId: widget.channelId,
        onShare: _shareChannel,
        onCopyLink: _copyChannelLink,
        onSearch: () {
          Navigator.of(context).pop();
          _openSearchFullscreen();
        },
        onManage: (_channel!.isOwner ||
            _channel!.isAdmin ||
            _channel!.isModerator)
            ? () {
                Navigator.of(context).pop();
                context.push(
                  ChannelDetailRoute.management(widget.channelId),
                );
              }
            : null,
        onAnalytics: (_channel!.isOwner || _channel!.isAdmin)
            ? () {
                Navigator.of(context).pop();
                context.push(AppAnalyticsRoute.path);
              }
            : null,
      ),
    );
  }

  Future<void> _shareChannel() async {
    final name = _channel?.name ?? 'Канал';
    final text = ShareLinkService.channelShareText(widget.channelId, name);
    await SystemShare.shareText(
      context,
      text: text,
      subject: name,
    );
  }

  Future<void> _copyChannelLink() async {
    final link = ShareLinkService.channelLink(widget.channelId);
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }
}

class _PrivateChannelPostsLocked extends StatelessWidget {
  const _PrivateChannelPostsLocked({required this.channel});

  final ChannelDetail channel;

  @override
  Widget build(BuildContext context) {
    final message = channel.isPending
        ? 'Заявка на вступление на рассмотрении. Посты появятся после одобрения.'
        : 'Это приватный канал. Откройте информацию о канале и запросите вступление.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

// Лента постов
class ChannelPostsList extends StatefulWidget {
  final int channelId;
  final ChannelDetail channel;
  final String? postType; // null = все посты, 'recipe' = только рецепты
  final VoidCallback? onPostDeleted;

  const ChannelPostsList({
    super.key,
    required this.channelId,
    required this.channel,
    this.postType,
    this.onPostDeleted,
  });

  @override
  State<ChannelPostsList> createState() => ChannelPostsListState();
}

class ChannelPostsListState extends State<ChannelPostsList> {
  List<PostModel> _posts = [];
  Object? _postsLoadError;
  bool _isLoading = false;
  bool _hasMoreOld = true; // Есть ли старые посты (при прокрутке вниз)
  int _offset = 0;
  int? _totalPosts;
  final ScrollController _scrollController = ScrollController();
  late final PageStorageKey _pageStorageKey;
  Timer? _scrollDebounce;
  bool _isLoadingMore = false;
  bool _initialScrollDone = false;

  void refreshPosts() {
    _loadPosts(refresh: true);
  }

  void addPost(PostModel post) {
    setState(() {
      _posts.removeWhere((existing) => existing.id == post.id);
      _posts.insert(0, post);
      final total = (_totalPosts ?? 0) + 1;
      _totalPosts = total;
      _hasMoreOld = _posts.length < total;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _pageStorageKey = PageStorageKey(
        'channel_posts_${widget.channelId}_${widget.postType ?? 'all'}');
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (!_scrollController.position.hasContentDimensions) return;

    // Debounce для оптимизации
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;

      // При использовании reverse: true, прокрутка вниз означает загрузку старых постов
      // Прокрутка вниз (к старым постам) - загружаем старые посты
      if (currentScroll >= maxScroll * 0.85) {
        if (!_isLoading && !_isLoadingMore && _hasMoreOld) {
          _loadOldPosts();
        }
      }
    });
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading && !refresh) return;
    if (!widget.channel.canViewPosts) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _posts = [];
        });
      }
      return;
    }

    setState(() {
      _isLoading = refresh;
      _isLoadingMore = !refresh;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMoreOld = true;
        _totalPosts = null;
        _initialScrollDone = false;
        _postsLoadError = null;
      }
    });

    try {
      // Загружаем с сервера (кэш пропускаем для правильной логики Telegram)
      await _loadPostsFromServer(refresh: refresh);
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        setState(() {
          _hasMoreOld = false;
          if (refresh) {
            _postsLoadError = e;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadPostsFromServer({bool refresh = false}) async {
    final response = await ChannelService.getChannelPosts(
      channelId: widget.channelId,
      limit: 20,
      offset:
          0, // При первой загрузке всегда offset=0 (бэкенд вернет последние посты)
      postType: widget.postType,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Таймаут загрузки постов');
      },
    );

    final posts = response.posts
        .map((p) {
          try {
            return PostModel.fromJson(p);
          } catch (e) {
            debugPrint('Ошибка парсинга поста: $e');
            return null;
          }
        })
        .whereType<PostModel>()
        .toList();

    if (mounted) {
      setState(() {
        _posts = posts;
        _totalPosts = response.total;
        _offset = 0;

        // Проверяем, есть ли еще старые посты (при прокрутке вниз)
        _hasMoreOld = _posts.length < response.total;
        _postsLoadError = null;
      });

      // Прокручиваем вниз к новым постам после первой загрузки
      // При reverse: true, нужно прокрутить к началу (index 0), так как новые посты внизу
      if (!_initialScrollDone && _posts.isNotEmpty) {
        // Используем несколько кадров для надежной прокрутки
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients && mounted) {
              // При reverse: true, прокручиваем к началу списка (к новым постам внизу)
              _scrollController.jumpTo(0);
              _initialScrollDone = true;
            }
          });
        });
      }
    }
  }

  // Загрузка старых постов (при прокрутке вниз)
  Future<void> _loadOldPosts() async {
    if (_isLoadingMore || !_hasMoreOld || _totalPosts == null) return;

    setState(() => _isLoadingMore = true);

    try {
      // Увеличиваем offset для загрузки более старых постов
      final newOffset = _posts.length;

      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 20,
        offset: newOffset,
        postType: widget.postType,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут загрузки постов');
        },
      );

      if (mounted && response.posts.isNotEmpty) {
        setState(() {
          // При reverse: true, элементы массива отображаются в обратном порядке
          // Чтобы старые посты отображались вверху, добавляем их в конец массива
          // _posts[0] отображается внизу (новые), _posts[last] отображается вверху (старые)
          final newPosts = response.posts
              .map((p) {
                try {
                  return PostModel.fromJson(p);
                } catch (e) {
                  debugPrint('Ошибка парсинга поста: $e');
                  return null;
                }
              })
              .whereType<PostModel>()
              .toList();
          _posts.addAll(newPosts);
          _offset = _posts.length;

          // Проверяем, есть ли еще старые посты
          _hasMoreOld = _posts.length < _totalPosts!;
        });
      } else {
        setState(() => _hasMoreOld = false);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки старых постов: $e');
      setState(() => _hasMoreOld = false);
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty && _isLoading) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 3,
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _SkeletonPostCard(),
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      if (_postsLoadError != null) {
        return AppEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Не удалось загрузить посты',
          subtitle: userVisibleError(
            _postsLoadError!,
            fallback: 'Проверьте сеть',
          ),
          action: FilledButton(
            onPressed: () => _loadPosts(refresh: true),
            child: const Text('Повторить'),
          ),
        );
      }
      return const ChannelTabEmptyPlaceholder(
        icon: Icons.inbox_outlined,
        title: 'Здесь пока нет постов',
        subtitle: 'Как только автор что-то опубликует — вы увидите это здесь.',
      );
    }

    return ListView.builder(
      key: _pageStorageKey,
      controller: _scrollController,
      reverse:
          true, // Используем reverse, чтобы новые посты были внизу визуально
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _posts.length + (_hasMoreOld && _isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          return _isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox.shrink();
        }

        final post = _posts[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ChannelPostCard(
              post: post,
              channelId: widget.channelId,
              channel: widget.channel,
              onCommentTap: () async {
                await context.push(PostCommentsRoute.pathFor(post.id));
              },
              onCardTap: () async {
                await context.push(
                  ChannelDetailRoute.post(widget.channelId, post.id),
                );
              },
              onPostDeleted: widget.onPostDeleted ??
                  () {
                    refreshPosts();
                  },
            ),
          ),
        );
      },
    );
  }
}

// Skeleton карточка для загрузки
class _SkeletonPostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = AppCardDecorations.defaultRadius;
    final placeholder = theme.colorScheme.surfaceContainerHighest;
    return AppElevatedCard(
      margin: const EdgeInsets.only(bottom: 18),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: placeholder,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(radius),
              ),
            ),
          ),
          // Skeleton для контента
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skelLine(placeholder, width: double.infinity, height: 20),
                const SizedBox(height: 8),
                _skelLine(placeholder, width: 200, height: 20),
                const SizedBox(height: 12),
                _skelLine(placeholder, width: double.infinity, height: 14),
                const SizedBox(height: 6),
                _skelLine(placeholder, width: double.infinity, height: 14),
                const SizedBox(height: 6),
                _skelLine(placeholder, width: 150, height: 14),
                const SizedBox(height: 12),
                _skelLine(placeholder, width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _skelLine(Color color, {required double width, required double height}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

// Модель для медиа-элемента
class _MediaItem {
  final String url;
  final String type; // 'image' или 'video'
  final int postId;

  _MediaItem({
    required this.url,
    required this.type,
    required this.postId,
  });
}

// Медиа-галерея канала (сетка изображений/видео)
class ChannelMediaList extends StatefulWidget {
  final int channelId;

  const ChannelMediaList({
    super.key,
    required this.channelId,
  });

  @override
  State<ChannelMediaList> createState() => ChannelMediaListState();
}

class ChannelMediaListState extends State<ChannelMediaList> {
  List<PostModel> _posts = [];
  List<_MediaItem> _mediaItems =
      []; // Список всех медиа-элементов из всех постов
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();

  void refreshMedia() {
    _loadMedia(refresh: true);
  }

  @override
  void initState() {
    super.initState();
    _loadMedia();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (!_scrollController.position.hasContentDimensions) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.85) {
      if (!_isLoading && _hasMore) {
        _loadMedia();
      }
    }
  }

  Future<void> _loadMedia({bool refresh = false}) async {
    if (_isLoading && !refresh) return;

    setState(() {
      _isLoading = refresh;
      if (refresh) {
        _posts = [];
        _mediaItems = [];
        _offset = 0;
        _hasMore = true;
      }
    });

    try {
      // Загружаем посты с типом photo или reel, или фильтруем посты с медиа
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 20,
        offset: refresh ? 0 : _offset,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут загрузки медиа');
        },
      );

      // Фильтруем посты, которые содержат медиа (изображения или видео)
      final postsWithMedia = response.posts
          .map((p) {
            try {
              return PostModel.fromJson(p);
            } catch (e) {
              debugPrint('Ошибка парсинга поста: $e');
              return null;
            }
          })
          .whereType<PostModel>()
          .toList();

      // Извлекаем все медиа-элементы из всех постов
      final List<_MediaItem> newMediaItems = [];
      for (final post in postsWithMedia) {
        final body = post.body;
        if (body == null) continue;
        final media = body['media'] as List<dynamic>?;
        if (media == null || media.isEmpty) continue;

        // Добавляем каждое изображение и видео как отдельный элемент
        for (final mediaItem in media) {
          try {
            final mediaType = mediaItem['type'] as String?;
            final mediaUrl = mediaItem['url'] as String?;
            if ((mediaType == 'image' || mediaType == 'video') &&
                mediaUrl != null &&
                mediaUrl.isNotEmpty) {
              final resolvedUrl = ServerConfig.resolveMediaUrl(mediaUrl);
              newMediaItems.add(_MediaItem(
                url: resolvedUrl,
                type: mediaType!,
                postId: post.id,
              ));
            }
          } catch (e) {
            debugPrint('Ошибка обработки медиа-элемента: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _posts = postsWithMedia;
            _mediaItems = newMediaItems;
          } else {
            _posts.addAll(postsWithMedia);
            _mediaItems.addAll(newMediaItems);
          }
          _offset = _posts.length;
          _hasMore = _posts.length < response.total;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки медиа: $e');
      if (mounted) {
        setState(() {
          _hasMore = false;
        });
        if (refresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userVisibleError(e, fallback: 'Не удалось загрузить медиа')),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaItems.isEmpty && _isLoading) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: 9,
        itemBuilder: (context, index) => Container(
          color: Colors.grey[300],
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_mediaItems.isEmpty) {
      return const ChannelTabEmptyPlaceholder(
        icon: Icons.photo_library_outlined,
        title: 'Здесь пока нет медиа',
        subtitle: 'Медиа из постов канала будут отображаться здесь.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadMedia(refresh: true),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: _mediaItems.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _mediaItems.length) {
            return _hasMore
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink();
          }

          final mediaItem = _mediaItems[index];
          final thumbPx = channelMediaThumbDecodeSize(context);

          return GestureDetector(
            onTap: () async {
              await context.push(
                ChannelDetailRoute.post(
                  widget.channelId,
                  mediaItem.postId,
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: imageUrlForChannelMediaGrid(mediaItem.url),
                  fit: BoxFit.cover,
                  memCacheWidth: thumbPx,
                  memCacheHeight: thumbPx,
                  maxWidthDiskCache: 2048,
                  maxHeightDiskCache: 2048,
                  filterQuality: FilterQuality.high,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.error_outline, size: 24),
                  ),
                ),
                if (mediaItem.type == 'video')
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
