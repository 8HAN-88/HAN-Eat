// Экран сохраненных постов
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/post_model.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/auth_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../../widgets/post_card_skeleton.dart';

class SavedPostsScreen extends ConsumerStatefulWidget {
  final int? userId; // Если null, то текущий пользователь
  
  const SavedPostsScreen({
    Key? key,
    this.userId,
  }) : super(key: key);
  
  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen>
    with SingleTickerProviderStateMixin {
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int? _currentUserId;
  final ScrollController _scrollController = ScrollController();
  bool _isOffline = false;
  late TabController _tabController;
  String? _currentPostType; // null = все, 'post' = посты, 'reel' = рилсы
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _currentPostType = null; // Начинаем с "Общее"
    _loadCurrentUserId();
    _checkConnectivity();
    _loadPosts();
    _scrollController.addListener(_onScroll);
    
    // Слушаем изменения подключения
    Connectivity().onConnectivityChanged.listen((result) {
      final isOffline = result == ConnectivityResult.none;
      if (mounted) {
        setState(() => _isOffline = isOffline);
        // Синхронизируем при подключении
        if (!isOffline) {
          _syncWithServer();
        }
      }
    });
  }
  
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        switch (_tabController.index) {
          case 0:
            _currentPostType = null; // все
            break;
          case 1:
            _currentPostType = 'recipe'; // рецепты
            break;
          case 2:
            _currentPostType = 'reel'; // рилсы
            break;
        }
      });
      _loadPosts(refresh: true);
    }
  }
  
  Future<void> _checkConnectivity() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    if (mounted) {
      setState(() => _isOffline = result == ConnectivityResult.none);
    }
  }
  
  Future<void> _syncWithServer() async {
    try {
      await SavedPostsService.syncWithServer();
      if (mounted) {
        _loadPosts(refresh: true);
      }
    } catch (e) {
      debugPrint('Failed to sync saved posts: $e');
    }
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadCurrentUserId() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() => _currentUserId = user.id);
    }
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }
  
  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;
    
    final userId = widget.userId ?? _currentUserId;
    if (userId == null) {
      // Показываем сообщение о необходимости входа
      return;
    }
    
    setState(() {
      _isLoading = true;
      if (refresh) {
        _posts = [];
        _offset = 0;
        _hasMore = true;
      }
    });
    
    try {
      final response = await SavedPostsService.getSavedPosts(
        userId: userId,
        limit: 20,
        offset: refresh ? 0 : _offset,
        postType: _currentPostType,
      );
      
      setState(() {
        if (refresh) {
          _posts = response.posts;
        } else {
          _posts.addAll(response.posts);
        }
        _offset = _posts.length;
        _hasMore = _posts.length < response.total;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _loadMore() async {
    await _loadPosts(refresh: false);
  }
  
  Widget _buildPostsList() {
    if (_posts.isEmpty && _isLoading) {
      return const PostListSkeletonLoader(itemCount: 5);
    }
    
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет сохраненных постов',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: ListView.builder(
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
              // Если пост из канала - открываем канал, иначе профиль автора
              if (post.channelId != null || post.communityId != null) {
                context.push('/channel/${post.channelId ?? post.communityId}');
              } else {
                context.push('/profile?userId=${post.userId}');
              }
            },
          );
        },
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final userId = widget.userId ?? _currentUserId;
    
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сохраненные')),
        body: const Center(
          child: Text('Войдите, чтобы видеть сохраненные посты'),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Общее'),
            Tab(text: 'Рецепты'),
            Tab(text: 'Рилсы'),
          ],
        ),
        actions: [
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                Icons.cloud_off,
                color: Colors.orange,
                size: 20,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _isOffline ? null : () => _syncWithServer(),
            tooltip: 'Синхронизировать',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsList(),
          _buildPostsList(),
          _buildPostsList(),
        ],
      ),
    );
  }
}

