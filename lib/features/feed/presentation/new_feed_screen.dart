// Новый экран ленты с постами из API
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/feed_service.dart';
import '../../../models/post_model.dart';
import 'new_post_card.dart';
import '../../../app/app_router.dart';
import '../../../widgets/post_card_skeleton.dart';

class NewFeedScreen extends ConsumerStatefulWidget {
  const NewFeedScreen({Key? key, this.hideScaffold = false}) : super(key: key);
  
  /// Если true, не показывать Scaffold и AppBar (для использования внутри табов)
  final bool hideScaffold;
  
  @override
  ConsumerState<NewFeedScreen> createState() => _NewFeedScreenState();
}

class _NewFeedScreenState extends ConsumerState<NewFeedScreen> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;
  String _feedType = 'all';
  bool _hasLoaded = false;
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Загружаем данные сразу при инициализации
    if (!_hasLoaded) {
      _hasLoaded = true;
      _loadFeed();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Если данные еще не загружены, загружаем их при подключении к дереву виджетов
    if (!_hasLoaded && !_isLoading && _posts.isEmpty) {
      _hasLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadFeed();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }
  
  Future<void> _loadFeed({bool refresh = false}) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts = [];
        _nextCursor = null;
        _hasMore = true;
      }
    });
    
    try {
      final response = await FeedService.getFeed(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
        feedType: _feedType,
      );
      
      setState(() {
        if (refresh) {
          _posts = response.items;
        } else {
          _posts.addAll(response.items);
        }
        _nextCursor = response.nextCursor;
        _hasMore = response.hasMore;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки ленты: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadMore() async {
    await _loadFeed(refresh: false);
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Необходимо для AutomaticKeepAliveClientMixin
    
    // Если данные еще не загружены, загружаем их
    if (!_hasLoaded && !_isLoading && _posts.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _hasLoaded = true;
          _loadFeed();
        }
      });
    }
    
    final bodyContent = RefreshIndicator(
      onRefresh: () => _loadFeed(refresh: true),
      child: _posts.isEmpty && _isLoading
          ? const PostListSkeletonLoader(itemCount: 5)
          : _posts.isEmpty
              ? const Center(child: Text('Нет постов'))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _posts.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _posts.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    
                    final post = _posts[index];
                    return NewPostCard(
                      post: post,
                      onCommentTap: () {
                        context.push('/post/${post.id}/comments');
                      },
                      onAuthorTap: () {
                        // Если репост - открываем профиль того, кто репостнул
                        if (post.repostedBy != null) {
                          context.push('/profile?userId=${post.repostedBy!.id}');
                        } else if (post.channelId != null || post.communityId != null) {
                          // Если пост из канала - открываем канал
                          context.push('/channel/${post.channelId ?? post.communityId}');
                        } else {
                          // Если пост из профиля - открываем профиль автора
                          context.push('/profile?userId=${post.userId}');
                        }
                      },
                    );
                  },
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
            onPressed: () {
              context.push('/reels');
            },
            tooltip: 'Рилсы',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              context.push(SearchRoute.path);
            },
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
              const PopupMenuItem(value: 'all', child: Text('Все')),
              const PopupMenuItem(value: 'photos', child: Text('Фото')),
              const PopupMenuItem(value: 'recipes', child: Text('Рецепты')),
              const PopupMenuItem(value: 'reels', child: Text('Рилсы')),
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
        onPressed: () {
          context.push(CreatePostRoute.path);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

