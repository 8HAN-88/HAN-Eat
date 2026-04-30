// Экран ленты подписок с постами от подписанных пользователей
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/feed_service.dart';
import '../../../models/post_model.dart';
import 'new_post_card.dart';
import '../../../app/app_router.dart';
import '../../../widgets/post_card_skeleton.dart';
import '../../../services/auth_service.dart';

/// Лента постов от подписанных пользователей
class SubscriptionsFeedScreen extends ConsumerStatefulWidget {
  const SubscriptionsFeedScreen({super.key});

  @override
  ConsumerState<SubscriptionsFeedScreen> createState() => _SubscriptionsFeedScreenState();
}

class _SubscriptionsFeedScreenState extends ConsumerState<SubscriptionsFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  List<PostModel> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);
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
      }
    });
    
    try {
      final response = await FeedService.getFeed(
        cursor: refresh ? null : _nextCursor,
        limit: 20,
        feedType: 'all',
        followingOnly: true, // Только посты от подписок
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
    final currentUser = AuthService.instance.currentUser;

    if (currentUser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Войдите, чтобы видеть посты от подписок',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Подписки',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Подпишитесь на авторов, чтобы видеть их посты здесь',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                context.push(SearchRoute.path);
              },
              child: const Text('Найти авторов'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFeed(refresh: true),
      child: _posts.isEmpty && _isLoading
          ? const PostListSkeletonLoader(itemCount: 5)
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
                    // Если пост из канала, переходим к каналу, иначе к профилю автора
                    if (post.channelId != null) {
                      context.push('/channel/${post.channelId}');
                    } else {
                      context.push('/profile?userId=${post.userId}');
                    }
                  },
                );
              },
            ),
    );
  }
}

