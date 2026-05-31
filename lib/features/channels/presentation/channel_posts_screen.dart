// Простой экран с постами канала (как в Telegram - только посты)
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../app/app_router.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../models/post_model.dart';
import 'channel_post_card.dart';
import 'channel_detail_screen_tabs.dart';
import 'channel_search_screen.dart';
import 'channel_settings_bottom_sheet.dart';
import '../../../core/theme/app_card_decorations.dart';
import '../../../widgets/app_empty_state.dart';

// Импортируем ChannelDetail из channel_service
export '../../../services/channel_service.dart' show ChannelDetail;

class ChannelPostsScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelPostsScreen({
    super.key,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelPostsScreen> createState() => _ChannelPostsScreenState();
}

class _ChannelPostsScreenState extends ConsumerState<ChannelPostsScreen> {
  ChannelDetail? _channel;
  Object? _channelLoadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _channelLoadError = null;
    });

    try {
      // С сервера: права is_owner / is_admin зависят от токена; кэш мог
      // сохранить ответ без авторизации.
      final channel = await ChannelCacheService.getChannel(
        widget.channelId,
        forceRefresh: true,
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
              onPressed: _loadChannel,
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            // Переход к полному экрану канала с вкладками
            context.push(ChannelDetailRoute.info(widget.channelId));
          },
          child: Row(
            children: [
              // Название канала по центру
              Expanded(
                child: Center(
                  child: Text(
                    _channel!.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Аватар канала справа
              CircleAvatar(
                radius: 16,
                backgroundImage: _channel!.avatarUrl != null
                    ? CachedNetworkImageProvider(_channel!.avatarUrl!)
                    : null,
                child: _channel!.avatarUrl == null
                    ? Text(
                        _channel!.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 14),
                      )
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Меню канала',
            onPressed: _showChannelSettings,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_channel!.isOwner || _channel!.isAdmin) ...[
            FloatingActionButton(
              heroTag: 'channel_posts_create',
              onPressed: _openCreatePost,
              tooltip: 'Создать пост',
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'channel_posts_search',
            mini: true,
            onPressed: () => _openSearch(context),
            tooltip: 'Поиск по каналу',
            child: const Icon(Icons.search),
          ),
        ],
      ),
      body: _ChannelPostsList(
        channelId: widget.channelId,
        postType: null, // Все посты
        channel: _channel!,
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChannelSearchScreen(
          channelId: widget.channelId,
          initialQuery: '',
          channel: _channel!,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openCreatePost() async {
    await context.push(ChannelDetailRoute.createPost(widget.channelId));
    if (!mounted) return;
    await _loadChannel();
  }

  void _showChannelSettings() {
    final rootContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ChannelSettingsBottomSheet(
        channel: _channel!,
        channelId: widget.channelId,
        onShare: _shareChannel,
        onCopyLink: _copyChannelLink,
        onSearch: () => _openSearch(rootContext),
        onManage: (_channel!.isOwner || _channel!.isAdmin)
            ? () {
                Navigator.of(sheetContext).pop();
                rootContext
                    .push(ChannelDetailRoute.management(widget.channelId));
              }
            : null,
      ),
    );
  }

  Future<void> _shareChannel() async {
    final link = 'https://han-eat.app/channel/${widget.channelId}';
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
}

// Список постов канала (переиспользуем из channel_detail_screen)
class _ChannelPostsList extends StatefulWidget {
  final int channelId;
  final String? postType;
  final ChannelDetail channel;

  const _ChannelPostsList({
    required this.channelId,
    this.postType,
    required this.channel,
  });

  @override
  State<_ChannelPostsList> createState() => _ChannelPostsListState();
}

class _ChannelPostsListState extends State<_ChannelPostsList>
    with AutomaticKeepAliveClientMixin {
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMoreOld = true; // Есть ли старые посты (при прокрутке вниз)
  int _offset = 0;
  int? _totalPosts;
  final ScrollController _scrollController = ScrollController();
  bool _initialScrollDone = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
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
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;

    // При использовании reverse: true:
    // - Прокрутка вверх (к maxScrollExtent) = загрузка старых постов
    // - Прокрутка вниз (к 0) = новые посты (уже загружены)
    if (currentScroll >= maxScroll * 0.85) {
      if (!_isLoading && _hasMoreOld) {
        _loadOldPosts();
      }
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading && !refresh) return;

    setState(() {
      _isLoading = refresh;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMoreOld = true;
        _totalPosts = null;
        _initialScrollDone = false;
      }
    });

    try {
      final response = await ChannelService.getChannelPosts(
        channelId: widget.channelId,
        limit: 20,
        offset: 0, // При первой загрузке offset=0 (бэкенд вернет новые посты)
        postType: widget.postType,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут загрузки постов');
        },
      );

      if (mounted) {
        setState(() {
          // Бэкенд возвращает посты отсортированные по published_at.desc() (новые первыми)
          // При reverse: true, они будут отображаться внизу визуально
          _posts = response.posts.map((p) => PostModel.fromJson(p)).toList();
          _totalPosts = response.total;
          _offset = 0;

          // Проверяем, есть ли еще старые посты (при прокрутке вверх)
          _hasMoreOld = _posts.length < response.total;
        });

        // Прокручиваем к новым постам после первой загрузки
        // При reverse: true, новые посты внизу, поэтому прокручиваем к началу (0)
        if (!_initialScrollDone && _posts.isNotEmpty) {
          // Используем несколько кадров для надежной прокрутки
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients && mounted) {
                // При reverse: true, jumpTo(0) прокрутит к началу списка (новые посты внизу)
                _scrollController.jumpTo(0);
                _initialScrollDone = true;
              }
            });
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        setState(() {
          _hasMoreOld = false;
        });
        if (refresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userVisibleError(e, fallback: 'Не удалось загрузить посты')),
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

  // Загрузка старых постов (при прокрутке вниз)
  Future<void> _loadOldPosts() async {
    if (_isLoading || !_hasMoreOld || _totalPosts == null) return;

    setState(() => _isLoading = true);

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
          final newPosts =
              response.posts.map((p) => PostModel.fromJson(p)).toList();
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    if (_posts.isEmpty && _isLoading) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 3,
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: AppElevatedCard(
              margin: const EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 200,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return const ChannelTabEmptyPlaceholder(
        icon: Icons.inbox_outlined,
        title: 'Здесь пока нет постов',
        subtitle: 'Как только автор что-то опубликует — вы увидите это здесь.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        reverse:
            true, // Используем reverse, чтобы новые посты были внизу визуально
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _posts.length + (_hasMoreOld && _isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
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
                onCommentTap: () =>
                    context.push(PostCommentsRoute.pathFor(post.id)),
                onPostDeleted: () {
                  _loadPosts(refresh: true);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
