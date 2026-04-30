import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../services/feed_service.dart';
import '../../../services/feed_sync_service.dart';

/// Состояние ленты
class FeedState {
  const FeedState({
    required this.posts,
    required this.loading,
    this.error,
    this.hasMore = true,
    this.lastPostId,
  });

  factory FeedState.initial() => const FeedState(
        posts: [],
        loading: false,
        hasMore: true,
      );

  final List<Post> posts;
  final bool loading;
  final String? error;
  final bool hasMore;
  final String? lastPostId;

  FeedState copyWith({
    List<Post>? posts,
    bool? loading,
    String? error,
    bool? hasMore,
    String? lastPostId,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      loading: loading ?? this.loading,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      lastPostId: lastPostId ?? this.lastPostId,
    );
  }
}

/// Провайдер контроллера ленты
final feedControllerProvider =
    StateNotifierProvider<FeedController, FeedState>((ref) {
  return FeedController();
});

/// Контроллер ленты
class FeedController extends StateNotifier<FeedState> {
  FeedController() : super(FeedState.initial());

  FeedSortMode _currentSortMode = FeedSortMode.personalized;

  /// Загрузить ленту (с оффлайн поддержкой)
  Future<void> loadFeed({FeedSortMode? sortMode}) async {
    _currentSortMode = sortMode ?? _currentSortMode;
    
    state = state.copyWith(loading: true, error: null);

    try {
      // Используем синхронизацию, которая автоматически работает с кешем
      final posts = await FeedSyncService.instance.getFeed(
        sortMode: _currentSortMode,
        useCache: true,
      );

      state = state.copyWith(
        posts: posts.take(20).toList(),
        loading: false,
        hasMore: posts.length >= 20,
        lastPostId: posts.isNotEmpty ? posts.first.idString : null,
      );

      // Фоновая синхронизация для обновления кеша
      FeedSyncService.instance.syncFeedInBackground(sortMode: _currentSortMode);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Не удалось загрузить ленту: $e',
      );
    }
  }

  /// Загрузить больше постов
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;

    state = state.copyWith(loading: true);

    try {
      final newPostModels = await FeedService.getMainFeed(
        mode: _currentSortMode,
        limit: 20,
        lastPostId: state.lastPostId,
      );

      // Преобразуем PostModel в Post
      final newPosts = newPostModels.map((pm) => pm.toPost()).toList();

      if (newPosts.isEmpty) {
        state = state.copyWith(
          loading: false,
          hasMore: false,
        );
        return;
      }

      // Объединяем с существующими (убираем дубликаты)
      final existingIds = state.posts.map((p) => p.id).toSet();
      final uniqueNewPosts = newPosts
          .where((p) => !existingIds.contains(p.id))
          .toList();

      state = state.copyWith(
        posts: [...state.posts, ...uniqueNewPosts],
        loading: false,
        hasMore: newPosts.length >= 20,
        lastPostId: uniqueNewPosts.isNotEmpty ? uniqueNewPosts.last.idString : state.lastPostId,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Не удалось загрузить больше постов: $e',
      );
    }
  }

  /// Обновить конкретный пост (например, после лайка)
  Future<void> refreshPost(String postId) async {
    // TODO: Реализовать обновление одного поста
    // Пока просто перезагружаем ленту
    await loadFeed();
  }

  /// Удалить пост из ленты (например, после скрытия)
  void removePost(String postId) {
    final postIdInt = int.tryParse(postId);
    if (postIdInt == null) return;
    final updatedPosts = state.posts.where((p) => p.id != postIdInt).toList();
    state = state.copyWith(posts: updatedPosts);
  }
}

