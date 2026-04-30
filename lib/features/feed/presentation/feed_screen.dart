import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../services/feed_service.dart';
import '../../../services/feed_sync_service.dart';
import '../../../services/auth_service.dart';
import '../application/feed_controller.dart';
import 'post_card.dart';

/// Экран ленты постов (по мотивам ВКонтакте)
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.hideScaffold = false});

  /// Если true, не показывать Scaffold и AppBar (для использования внутри табов)
  final bool hideScaffold;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final ScrollController _scrollController = ScrollController();
  FeedSortMode _sortMode = FeedSortMode.personalized;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadFeed() {
    ref.read(feedControllerProvider.notifier).loadFeed(sortMode: _sortMode);
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedControllerProvider);

    final bodyContent = _buildBody(feedState);
    
    final content = widget.hideScaffold
        ? Column(
            children: [
              // Панель управления (если используется без Scaffold)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Переключатель режимов
                    Expanded(
                      child: SegmentedButton<FeedSortMode>(
                        segments: const [
                          ButtonSegment(
                            value: FeedSortMode.personalized,
                            label: Text('Для вас'),
                          ),
                          ButtonSegment(
                            value: FeedSortMode.recent,
                            label: Text('Свежие'),
                          ),
                        ],
                        selected: {_sortMode},
                        onSelectionChanged: (Set<FeedSortMode> newSelection) {
                          setState(() {
                            _sortMode = newSelection.first;
                          });
                          _loadFeed();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Контент ленты
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _loadFeed();
                  },
                  child: bodyContent,
                ),
              ),
            ],
          )
        : RefreshIndicator(
            onRefresh: () async {
              _loadFeed();
            },
            child: bodyContent,
          );

    if (widget.hideScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Лента'),
        actions: [
          // Индикатор онлайн/оффлайн
          ValueListenableBuilder<bool>(
            valueListenable: FeedSyncService.instance.isOnline,
            builder: (context, isOnline, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.green : Colors.grey,
                  size: 20,
                ),
              );
            },
          ),
          // Переключатель режимов
          SegmentedButton<FeedSortMode>(
            segments: const [
              ButtonSegment(
                value: FeedSortMode.personalized,
                label: Text('Для вас'),
              ),
              ButtonSegment(
                value: FeedSortMode.recent,
                label: Text('Свежие'),
              ),
            ],
            selected: {_sortMode},
            onSelectionChanged: (Set<FeedSortMode> newSelection) {
              setState(() {
                _sortMode = newSelection.first;
              });
              _loadFeed();
            },
          ),
          const SizedBox(width: 8),
          // Поиск
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Navigate to search
            },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildBody(FeedState state) {
    if (state.loading && state.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Ошибка загрузки ленты',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(state.error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFeed,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (state.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.feed_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Лента пуста',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Подпишитесь на друзей или группы, чтобы видеть их посты'),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.posts.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.posts.length) {
          // Индикатор загрузки для следующей страницы
          _loadMore();
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final post = state.posts[index];
        return PostCard(
          post: post,
          onLike: () => _toggleLike(post),
          onComment: () => _openComments(post),
          onShare: () => _sharePost(post),
          onHide: () => _hidePost(post),
          onReport: () => _reportPost(post),
        );
      },
    );
  }

  void _loadMore() {
    ref.read(feedControllerProvider.notifier).loadMore();
  }

  Future<void> _toggleLike(Post post) async {
    final currentUid = AuthService.instance.currentUser?.uid;
    if (currentUid == null) return;

    final isLiked = await _isPostLiked(post.idString, currentUid);
    if (isLiked) {
      await FeedService.unlikePost(post.id, currentUid);
    } else {
      await FeedService.likePost(post.id, currentUid);
    }

    // Обновляем состояние
    ref.read(feedControllerProvider.notifier).refreshPost(post.idString);
  }

  Future<bool> _isPostLiked(String postId, String userId) async {
    // TODO: Implement
    return false;
  }

  void _openComments(Post post) {
    // TODO: Navigate to comments
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Комментарии')),
          body: Center(child: Text('Комментарии к посту ${post.id}')),
        ),
      ),
    );
  }

  void _sharePost(Post post) {
    // TODO: Implement share
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Функция репоста в разработке')),
    );
  }

  Future<void> _hidePost(Post post) async {
    final currentUid = AuthService.instance.currentUser?.uid;
    if (currentUid == null) return;

    await FeedService.hidePost(post.idString, currentUid);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Пост скрыт')),
    );

    // Обновляем ленту
    ref.read(feedControllerProvider.notifier).removePost(post.idString);
  }

  void _reportPost(Post post) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Пожаловаться на пост'),
        content: const Text('Выберите причину жалобы'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              final currentUid = AuthService.instance.currentUser?.uid;
              if (currentUid != null) {
                await FeedService.reportPost(post.idString, currentUid, 'spam');
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Жалоба отправлена')),
                  );
                }
              }
            },
            child: const Text('Пожаловаться'),
          ),
        ],
      ),
    );
  }
}

