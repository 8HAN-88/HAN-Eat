// Экран детального просмотра канала с лентой постов (согласно UI-прототипу)
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../services/like_service.dart';
import '../../../services/repost_service.dart';
import '../../../services/auth_service.dart';
import '../../../models/post_model.dart';
import '../../../services/server_config.dart';
import '../../../utils/image_url_helper.dart';
import '../../../utils/number_formatter.dart';
import '../../../widgets/telegram_photo_grid.dart';
import 'channel_post_detail_screen.dart';
import 'channel_settings_bottom_sheet.dart';
import 'channel_detail_screen_tabs.dart';
import 'channel_search_screen.dart';

class ChannelDetailScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelDetailScreen({
    Key? key,
    required this.channelId,
  }) : super(key: key);

  @override
  ConsumerState<ChannelDetailScreen> createState() =>
      _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends ConsumerState<ChannelDetailScreen>
    with SingleTickerProviderStateMixin {
  ChannelDetail? _channel;
  bool _isLoading = true;
  bool _isJoining = false;
  late TabController _tabController;
  final GlobalKey<_ChannelPostsListState> _postsListKey =
      GlobalKey<_ChannelPostsListState>();
  final GlobalKey<_ChannelMediaListState> _mediaListKey =
      GlobalKey<_ChannelMediaListState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadChannel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChannel({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    try {
      // Сначала пытаемся загрузить из кэша (быстро)
      if (!forceRefresh) {
        try {
          final cachedChannel = await ChannelCacheService.getChannel(
            widget.channelId,
            forceRefresh: false,
          );
          if (mounted && cachedChannel != null) {
            setState(() {
              _channel = cachedChannel;
              _isLoading = false;
            });
            // Загружаем свежие данные в фоне
            _loadChannel(forceRefresh: true);
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
        setState(() => _channel = channel);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки канала: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки канала: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openCreatePost() async {
    final result =
        await context.push('/channel/${widget.channelId}/create-post');
    if (result is PostModel) {
      _postsListKey.currentState?.addPost(result);
      _mediaListKey.currentState?.refreshMedia();
    } else if (result == true) {
      _postsListKey.currentState?.refreshPosts();
      _mediaListKey.currentState?.refreshMedia();
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
          SnackBar(content: Text('Ошибка: $e')),
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
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: const Center(child: Text('Канал не найден')),
      );
    }

    return Scaffold(
      floatingActionButton: (_channel!.isAdmin || _channel!.isOwner)
          ? FloatingActionButton(
              onPressed: _openCreatePost,
              child: const Icon(Icons.add),
              tooltip: 'Создать пост',
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Шапка канала с раскрывающейся информацией (как в Telegram)
            _ChannelHeader(
              channel: _channel!,
              onSettingsTap: () => _showChannelSettings(),
              isScrolled: innerBoxIsScrolled,
              isJoining: _isJoining,
              onSubscribeTap: _toggleSubscribe,
            ),
            // Вкладки
            SliverPersistentHeader(
              pinned: true,
              delegate: SliverTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Посты'),
                    Tab(text: 'Медиа'),
                    Tab(text: 'Рецепты'),
                    Tab(text: 'О канале'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Вкладка "Посты"
            _ChannelPostsList(
              key: _postsListKey,
              channelId: widget.channelId,
              postType: null, // Все посты
            ),
            // Вкладка "Медиа"
            _ChannelMediaList(
              key: _mediaListKey,
              channelId: widget.channelId,
            ),
            // Вкладка "Рецепты"
            _ChannelPostsList(
              channelId: widget.channelId,
              postType: 'recipe', // Только рецепты
            ),
            // Вкладка "О канале"
            ChannelAboutTab(channel: _channel!),
          ],
        ),
      ),
    );
  }

  void _showChannelSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChannelSettingsBottomSheet(
        channel: _channel!,
        channelId: widget.channelId,
        onShare: _shareChannel,
        onCopyLink: _copyChannelLink,
        onSearch: _searchInChannel,
        onManage: (_channel!.isOwner || _channel!.isAdmin)
            ? () {
                Navigator.of(context).pop();
                context.push('/channel/${widget.channelId}/management');
              }
            : null,
      ),
    );
  }

  Future<void> _shareChannel() async {
    final link = 'https://han-eat.app/channel/${widget.channelId}';
    // TODO: Реализовать нативное поделиться
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
      );
    }
  }

  Future<void> _copyChannelLink() async {
    final link = 'https://han-eat.app/channel/${widget.channelId}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }

  void _searchInChannel() {
    Navigator.of(context).pop();
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Поиск по каналу'),
        content: TextField(
          controller: searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Введите запрос для поиска...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            Navigator.of(context).pop();
            if (value.trim().isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChannelSearchScreen(
                    channelId: widget.channelId,
                    initialQuery: value.trim(),
                    channel: _channel!,
                  ),
                ),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final query = searchController.text.trim();
              Navigator.of(context).pop();
              if (query.isNotEmpty) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChannelSearchScreen(
                      channelId: widget.channelId,
                      initialQuery: query,
                      channel: _channel!,
                    ),
                  ),
                );
              }
            },
            child: const Text('Найти'),
          ),
        ],
      ),
    );
  }
}

// Шапка канала (фиксированная высота 110-140px)
class _ChannelHeader extends StatelessWidget {
  final ChannelDetail channel;
  final VoidCallback onSettingsTap;
  final bool isScrolled;
  final bool isJoining;
  final VoidCallback onSubscribeTap;

  const _ChannelHeader({
    required this.channel,
    required this.onSettingsTap,
    required this.isScrolled,
    required this.isJoining,
    required this.onSubscribeTap,
  });

  @override
  Widget build(BuildContext context) {
    const expandedHeight = 380.0; // Высота развернутой шапки с информацией

    return SliverAppBar(
      expandedHeight: expandedHeight,
      toolbarHeight: kToolbarHeight, // Компактная высота toolbar
      pinned: true,
      snap: false, // Отключаем snap для более плавного поведения
      floating:
          false, // Отключаем floating, чтобы панель уходила вверх при прокрутке вниз
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: onSettingsTap,
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final safeAreaTop = MediaQuery.of(context).padding.top;
          final expanded =
              constraints.biggest.height > kToolbarHeight + safeAreaTop;
          final shrinkOffset = expandedHeight - constraints.biggest.height;
          final shrinkPercentage =
              (shrinkOffset / (expandedHeight - kToolbarHeight - safeAreaTop))
                  .clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            centerTitle: true,
            titlePadding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            title: expanded
                ? null // В развернутом виде title не показываем, он в контенте
                : Text(
                    channel.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            background: Container(
              decoration: channel.coverUrl != null
                  ? BoxDecoration(
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(channel.coverUrl!),
                        fit: BoxFit.cover,
                      ),
                    )
                  : null,
              child: Container(
                decoration: channel.coverUrl != null
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                          ],
                        ),
                      )
                    : null,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top +
                          kToolbarHeight +
                          12,
                      left: 16,
                      right: 16,
                      bottom: 12,
                    ),
                    child: Opacity(
                      opacity: 1 - shrinkPercentage,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Аватар канала
                            CircleAvatar(
                              radius: 45,
                              backgroundColor: channel.coverUrl != null
                                  ? Colors.white.withOpacity(0.2)
                                  : null,
                              backgroundImage: channel.avatarUrl != null
                                  ? CachedNetworkImageProvider(
                                      channel.avatarUrl!)
                                  : null,
                              child: channel.avatarUrl == null
                                  ? Text(
                                      channel.name[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: channel.coverUrl != null
                                            ? Colors.white
                                            : null,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            // Название канала
                            Text(
                              channel.name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: channel.coverUrl != null
                                    ? Colors.white
                                    : null,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // Количество подписчиков
                            Text(
                              '${channel.membersCount} подписчиков',
                              style: TextStyle(
                                fontSize: 14,
                                color: channel.coverUrl != null
                                    ? Colors.white.withOpacity(0.9)
                                    : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Описание (если есть)
                            if (channel.description != null &&
                                channel.description!.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  channel.description!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: channel.coverUrl != null
                                        ? Colors.white.withOpacity(0.9)
                                        : Colors.grey[700],
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Кнопка Подписаться/Отписаться
                            SizedBox(
                              height: 36,
                              child: channel.isMember
                                  ? OutlinedButton(
                                      onPressed:
                                          isJoining ? null : onSubscribeTap,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                      ),
                                      child: isJoining
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : const Text(
                                              'Отписаться',
                                              style: TextStyle(fontSize: 14),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                    )
                                  : FilledButton(
                                      onPressed:
                                          isJoining ? null : onSubscribeTap,
                                      style: FilledButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                      ),
                                      child: isJoining
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              'Подписаться',
                                              style: TextStyle(fontSize: 14),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Блок описания канала
class _ChannelDescriptionBlock extends StatelessWidget {
  final ChannelDetail channel;
  final bool isJoining;
  final VoidCallback onSubscribeTap;

  const _ChannelDescriptionBlock({
    required this.channel,
    required this.isJoining,
    required this.onSubscribeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Описание (до 2-3 строк, 15-16px, серый)
          if (channel.description != null &&
              channel.description!.isNotEmpty) ...[
            Text(
              channel.description!,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
          // Кнопка Подписаться/Отписаться
          SizedBox(
            height: 36,
            child: channel.isMember
                ? OutlinedButton(
                    onPressed: isJoining ? null : onSubscribeTap,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: isJoining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Отписаться',
                            style: TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  )
                : FilledButton(
                    onPressed: isJoining ? null : onSubscribeTap,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: isJoining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Подписаться',
                            style: TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// Лента постов
class _ChannelPostsList extends StatefulWidget {
  final int channelId;
  final String? postType; // null = все посты, 'recipe' = только рецепты

  const _ChannelPostsList({
    Key? key,
    required this.channelId,
    this.postType,
  }) : super(key: key);

  @override
  State<_ChannelPostsList> createState() => _ChannelPostsListState();
}

class _ChannelPostsListState extends State<_ChannelPostsList> {
  List<PostModel> _posts = [];
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

    setState(() {
      _isLoading = refresh;
      _isLoadingMore = !refresh;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMoreOld = true;
        _totalPosts = null;
        _initialScrollDone = false;
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
        });
        if (refresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки постов: ${e.toString()}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Здесь пока нет постов',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Как только автор что-то опубликует — вы увидите это здесь.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
            child: _ChannelPostCard(
              post: post,
              channelId: widget.channelId,
              onTap: () async {
                await context.push(
                  '/channel/${widget.channelId}/post/${post.id}',
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// Карточка поста в ленте (92-94% ширины, скругление 16-20px)
class _ChannelPostCard extends StatefulWidget {
  final PostModel post;
  final int channelId;
  final VoidCallback onTap;

  const _ChannelPostCard({
    required this.post,
    required this.channelId,
    required this.onTap,
  });

  @override
  State<_ChannelPostCard> createState() => _ChannelPostCardState();
}

class _ChannelPostCardState extends State<_ChannelPostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late PostModel _post; // Локальное состояние поста

  @override
  void initState() {
    super.initState();
    _post = widget.post; // Инициализируем из widget
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    // Отмечаем пост как прочитанный при загрузке
    _markAsViewed();
  }

  Future<void> _markAsViewed() async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null) return;

      // Вызываем API для отметки поста как прочитанного
      final uri =
          Uri.parse('${ServerConfig.apiBaseUrl}/posts/${widget.post.id}/view');
      await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      // Игнорируем ошибки при отметке просмотра
      debugPrint('Ошибка отметки поста как прочитанного: $e');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    // Показываем точное время: часы и минуты
    try {
      return DateFormat('HH:mm', 'ru').format(date);
    } catch (e) {
      return DateFormat('HH:mm').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = _post; // Используем локальное состояние
    final body = post.body;
    final media = body?['media'] as List<dynamic>?;

    // Получаем все изображения (как в Telegram)
    List<String> imageUrls = [];
    if (media != null && media.isNotEmpty) {
      for (var item in media) {
        if (item is Map<String, dynamic> && item['type'] == 'image') {
          final url = item['url'] as String?;
          if (url != null && url.isNotEmpty) {
            imageUrls.add(url);
          }
        }
      }
    }

    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) {
        _animationController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _animationController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Отображаем фотографии как в Telegram (1, 2, 3+ фото) - центрируем для симметрии
              if (imageUrls.isNotEmpty)
                Center(
                  child: TelegramPhotoGrid(
                    imageUrls: imageUrls,
                    maxHeight: 300,
                    onTap: widget.onTap,
                    enableFullscreen: true,
                  ),
                ),
              // Контент карточки
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Название поста (жирный, до 2 строк)
                    if (post.title != null && post.title!.isNotEmpty)
                      Text(
                        post.title!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Краткое описание (1-3 строки)
                    if (post.description != null &&
                        post.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        post.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Статистика и дата
                    Row(
                      children: [
                        // Дата публикации
                        Icon(Icons.access_time,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(post.publishedAt ?? post.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const Spacer(),
                        // Статистика
                        // Просмотры
                        if (post.viewsCount > 0) ...[
                          Icon(Icons.visibility_outlined,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            NumberFormatter.formatCount(post.viewsCount),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (post.likesCount > 0) ...[
                          Icon(Icons.favorite_outline,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            NumberFormatter.formatCount(post.likesCount),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (post.commentsCount > 0) ...[
                          Icon(Icons.comment_outlined,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            NumberFormatter.formatCount(post.commentsCount),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (post.repostsCount > 0) ...[
                          Icon(Icons.repeat, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            NumberFormatter.formatCount(post.repostsCount),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Кнопки взаимодействия
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _InteractionButton(
                          icon: _post.isLiked
                              ? Icons.favorite
                              : Icons.favorite_outline,
                          label: '${_post.likesCount}',
                          color: _post.isLiked ? Colors.red : Colors.grey[600],
                          onTap: () => _handleLike(_post),
                        ),
                        _InteractionButton(
                          icon: Icons.comment_outlined,
                          label: '${_post.commentsCount}',
                          onTap: () => widget.onTap(),
                        ),
                        _InteractionButton(
                          icon: Icons.repeat,
                          label: '${_post.repostsCount}',
                          onTap: () => _handleRepost(_post),
                        ),
                        _InteractionButton(
                          icon: Icons.share_outlined,
                          label: 'Поделиться',
                          onTap: () => _handleShare(_post),
                        ),
                        // Меню с 3 точками (только для автора) - переместили сюда
                        FutureBuilder(
                          future: AuthService.getCurrentUser(),
                          builder: (context, snapshot) {
                            final currentUser = snapshot.data;
                            final isAuthor = currentUser != null &&
                                (currentUser.id == post.userId ||
                                    currentUser.id.toString() ==
                                        post.userId.toString());

                            if (!isAuthor) return const SizedBox.shrink();

                            return PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  // Загружаем данные поста для редактирования
                                  try {
                                    final response =
                                        await ChannelService.getChannelPosts(
                                      channelId:
                                          post.channelId ?? widget.channelId,
                                      limit: 50,
                                      offset: 0,
                                    );
                                    final postData = response.posts.firstWhere(
                                      (p) => p['id'] == post.id,
                                    );

                                    // Открываем экран редактирования
                                    final result = await context.push(
                                      '/channel/${post.channelId ?? widget.channelId}/post/${post.id}/edit',
                                      extra: postData,
                                    );

                                    // Обновляем пост после редактирования
                                    if (result == true && mounted) {
                                      // Перезагружаем пост
                                      final updatedResponse =
                                          await ChannelService.getChannelPosts(
                                        channelId:
                                            post.channelId ?? widget.channelId,
                                        limit: 50,
                                        offset: 0,
                                      );
                                      try {
                                        final updatedPostData =
                                            updatedResponse.posts.firstWhere(
                                          (p) => p['id'] == post.id,
                                        );
                                        setState(() {
                                          _post = PostModel.fromJson(
                                              updatedPostData
                                                  as Map<String, dynamic>);
                                        });
                                      } catch (e) {
                                        debugPrint(
                                            'Ошибка обновления поста: $e');
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Ошибка загрузки поста: $e')),
                                      );
                                    }
                                  }
                                } else if (value == 'delete') {
                                  // Показываем диалог подтверждения удаления
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Удалить пост?'),
                                      content: const Text(
                                          'Вы уверены, что хотите удалить этот пост? Это действие нельзя отменить.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: const Text('Отмена'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                          child: const Text('Удалить'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && mounted) {
                                    try {
                                      await ChannelService.deleteChannelPost(
                                        channelId:
                                            post.channelId ?? widget.channelId,
                                        postId: post.id,
                                      );
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('Пост удален')),
                                        );
                                        // Закрываем экран или обновляем список
                                        Navigator.of(context).pop();
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content:
                                                  Text('Ошибка удаления: $e')),
                                        );
                                      }
                                    }
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 20),
                                      SizedBox(width: 8),
                                      Text('Редактировать'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline,
                                          size: 20, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Удалить',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLike(PostModel post) async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Войдите, чтобы поставить лайк')),
          );
        }
        return;
      }

      final wasLiked = post.isLiked;

      // Оптимистичное обновление
      setState(() {
        // Обновляем локальное состояние
        _post = PostModel(
          id: post.id,
          type: post.type,
          title: post.title,
          description: post.description,
          status: post.status,
          createdAt: post.createdAt,
          publishedAt: post.publishedAt,
          userId: post.userId,
          communityId: post.communityId,
          body: post.body,
          tags: post.tags,
          likesCount: wasLiked ? post.likesCount - 1 : post.likesCount + 1,
          commentsCount: post.commentsCount,
          repostsCount: post.repostsCount,
          viewsCount: post.viewsCount,
          isLiked: !wasLiked,
          isSaved: post.isSaved,
          isReposted: post.isReposted,
          author: post.author,
          repostedBy: post.repostedBy,
          channel: post.channel,
        );
      });

      if (wasLiked) {
        await LikeService.unlikePost(post.id);
      } else {
        await LikeService.likePost(post.id);
      }
    } catch (e) {
      // Откатываем при ошибке
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _handleRepost(PostModel post) async {
    try {
      final token = await AuthService.getAccessToken();
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Войдите, чтобы сделать репост')),
          );
        }
        return;
      }

      await RepostService.createRepost(postId: post.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пост репостнут')),
        );
      }

      // Обновляем состояние
      setState(() {
        _post = PostModel(
          id: post.id,
          type: post.type,
          title: post.title,
          description: post.description,
          status: post.status,
          createdAt: post.createdAt,
          publishedAt: post.publishedAt,
          userId: post.userId,
          communityId: post.communityId,
          body: post.body,
          tags: post.tags,
          likesCount: post.likesCount,
          commentsCount: post.commentsCount,
          repostsCount: post.repostsCount + 1,
          viewsCount: post.viewsCount,
          isLiked: post.isLiked,
          isSaved: post.isSaved,
          isReposted: true,
          author: post.author,
          repostedBy: post.repostedBy,
          channel: post.channel,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _handleShare(PostModel post) async {
    final link =
        'https://han-eat.app/channel/${post.channelId}/post/${post.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ссылка скопирована')),
      );
    }
  }
}

// Кнопка взаимодействия
class _InteractionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _InteractionButton({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color ?? Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Skeleton карточка для загрузки
class _SkeletonPostCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton для изображения
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          // Skeleton для контента
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Skeleton для заголовка
                Container(
                  width: double.infinity,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 200,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                // Skeleton для описания
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 150,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                // Skeleton для даты
                Container(
                  width: 100,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
class _ChannelMediaList extends StatefulWidget {
  final int channelId;

  const _ChannelMediaList({
    Key? key,
    required this.channelId,
  }) : super(key: key);

  @override
  State<_ChannelMediaList> createState() => _ChannelMediaListState();
}

class _ChannelMediaListState extends State<_ChannelMediaList> {
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
              content: Text('Ошибка загрузки медиа: ${e.toString()}'),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Здесь пока нет медиа',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Медиа из постов канала будут отображаться здесь.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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

          return GestureDetector(
            onTap: () async {
              await context.push(
                '/channel/${widget.channelId}/post/${mediaItem.postId}',
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: getOptimizedImageUrl(mediaItem.url),
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  memCacheHeight: 200,
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
                    color: Colors.black.withOpacity(0.3),
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
