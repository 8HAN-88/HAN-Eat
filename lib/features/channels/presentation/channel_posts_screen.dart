// Простой экран с постами канала (как в Telegram - только посты)
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/channel_service.dart';
import '../../../services/channel_cache_service.dart';
import '../../../models/post_model.dart';
import '../../../utils/image_url_helper.dart';
import 'channel_post_card.dart';
import 'channel_search_screen.dart';

// Импортируем ChannelDetail из channel_service
export '../../../services/channel_service.dart' show ChannelDetail;

class ChannelPostsScreen extends ConsumerStatefulWidget {
  final int channelId;
  
  const ChannelPostsScreen({
    Key? key,
    required this.channelId,
  }) : super(key: key);
  
  @override
  ConsumerState<ChannelPostsScreen> createState() => _ChannelPostsScreenState();
}

class _ChannelPostsScreenState extends ConsumerState<ChannelPostsScreen> {
  ChannelDetail? _channel;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadChannel();
  }
  
  Future<void> _loadChannel({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    
    try {
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            // Переход к полному экрану канала с вкладками
            context.push('/channel/${widget.channelId}/info');
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
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () => _openSearch(context),
        tooltip: 'Поиск по каналу',
        child: const Icon(Icons.search),
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

class _ChannelPostsListState extends State<_ChannelPostsList> with AutomaticKeepAliveClientMixin {
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
          final newPosts = response.posts.map((p) => PostModel.fromJson(p)).toList();
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
            child: Container(
              height: 200,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
    
    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        reverse: true, // Используем reverse, чтобы новые посты были внизу визуально
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
                onCommentTap: () {
                  context.push('/post/${post.id}/comments');
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

