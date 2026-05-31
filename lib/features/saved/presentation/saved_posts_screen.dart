// Экран сохраненных постов
import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/post_model.dart';
import '../../../services/saved_posts_service.dart';
import '../../../services/auth_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../feed/presentation/new_post_card.dart';
import '../../../widgets/post_card_skeleton.dart';
import '../../../core/layout/long_label_tab_bar.dart';
import '../../../widgets/app_empty_state.dart';

class SavedPostsScreen extends ConsumerStatefulWidget {
  final int? userId; // Если null, то текущий пользователь
  final bool embedded; // true: использовать внутри другого экрана (без Scaffold/AppBar)
  
  const SavedPostsScreen({
    super.key,
    this.userId,
    this.embedded = false,
  });
  
  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen>
    with SingleTickerProviderStateMixin {
  List<PostModel> _posts = [];
  Object? _loadError;
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int? _currentUserId;
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
    
    // Слушаем изменения подключения
    Connectivity().onConnectivityChanged.listen((result) {
      final isOffline = result.contains(ConnectivityResult.none);
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
      setState(() => _isOffline = result.contains(ConnectivityResult.none));
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
    super.dispose();
  }
  
  Future<void> _loadCurrentUserId() async {
    final user = await AuthService.getCurrentUser();
    if (user != null) {
      setState(() => _currentUserId = user.id);
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
        _loadError = null;
      }
    });
    
    try {
      final response = await SavedPostsService.getSavedPosts(
        userId: userId,
        limit: 20,
        offset: refresh ? 0 : _offset,
        postType: _currentPostType,
      );

      final filteredPosts = _currentPostType == 'reel'
          ? response.posts.where((p) => p.type == 'reel').toList()
          : response.posts;
      
      setState(() {
        if (refresh) {
          _posts = filteredPosts;
        } else {
          _posts.addAll(filteredPosts);
        }
        _offset = _posts.length;
        _hasMore = _posts.length < response.total;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
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
      if (_loadError != null) {
        return AppEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Не удалось загрузить',
          subtitle: userVisibleError(_loadError!, fallback: 'Проверьте сеть'),
          action: FilledButton(
            onPressed: () => _loadPosts(refresh: true),
            child: const Text('Повторить'),
          ),
        );
      }
      return const AppEmptyState(
        icon: Icons.bookmark_border,
        title: 'Нет сохранённых постов',
        subtitle: 'Сохраняйте рецепты и посты — они появятся здесь',
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _loadPosts(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent * 0.8 &&
              !_isLoading &&
              _hasMore) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          primary: true,
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
              onCommentTap: () =>
                  context.push('/post/${post.id}/comments'),
              onPostDeleted: () {
                setState(() {
                  _posts.removeWhere((p) => p.id == post.id);
                });
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
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final userId = widget.userId ?? _currentUserId;
    
    if (userId == null) {
      return const Center(
        child: Text('Войдите, чтобы видеть сохраненные посты'),
      );
    }

    final content = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Избранное',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                if (_isOffline)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
                  ),
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: _isOffline ? null : () => _syncWithServer(),
                  tooltip: 'Синхронизировать',
                ),
              ],
            ),
          ),
        longLabelTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Общее'),
            Tab(text: 'Рецепты'),
            Tab(text: 'Рилсы'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPostsList(),
              _buildPostsList(),
              _buildPostsList(),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
        actions: [
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _isOffline ? null : () => _syncWithServer(),
            tooltip: 'Синхронизировать',
          ),
        ],
      ),
      body: content,
    );
  }
}

