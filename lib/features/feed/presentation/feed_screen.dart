import 'package:flutter/material.dart';
import '../../../utils/api_error_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/share/system_share.dart';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../services/auth_service.dart';
import '../../../services/feed_service.dart';
import '../../../services/feed_sync_service.dart';
import '../../../services/share_link_service.dart';
import '../../../widgets/report_content_dialog.dart';
import '../../../widgets/app_empty_state.dart';
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
            onPressed: () => context.push(SearchRoute.path),
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Не удалось загрузить ленту',
              subtitle: state.error,
              action: FilledButton(
                onPressed: _loadFeed,
                child: const Text('Повторить'),
              ),
            ),
          ),
        ],
      );
    }

    if (state.posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: const AppEmptyState(
              icon: Icons.feed_outlined,
              title: 'Лента пуста',
              subtitle:
                  'Подпишитесь на авторов и каналы — их посты появятся здесь',
            ),
          ),
        ],
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
          onBlockAuthor: () => _blockAuthor(post),
          onBookmarkChanged: (postId) =>
              ref.read(feedControllerProvider.notifier).refreshPost(postId),
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

    try {
      if (post.isLiked) {
        await FeedService.unlikePost(post.id, currentUid);
      } else {
        await FeedService.likePost(post.id, currentUid);
      }
      await ref.read(feedControllerProvider.notifier).refreshPost(post.idString);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userVisibleError(e))),
        );
      }
    }
  }

  Future<void> _blockAuthor(Post post) async {
    await ref.read(feedControllerProvider.notifier).blockAuthor(post.userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Посты этого автора скрыты в вашей ленте'),
        ),
      );
    }
  }

  void _openComments(Post post) {
    context.push('/post/${post.id}/comments');
  }

  Future<void> _sharePost(Post post) async {
    final link = post.type == 'reel'
        ? ShareLinkService.reelLink(post.id)
        : ShareLinkService.postLink(post.id);
    final title = (post.title ?? post.description ?? 'Пост').trim();
    final text = '$title\n\nОткрыть в H.A.N. Eat: $link';
    await SystemShare.shareText(
      context,
      text: text,
      subject: 'Пост',
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
    reportPostWithDialog(context, post.id);
  }
}

