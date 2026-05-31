import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../utils/api_error_parser.dart';
import '../../../models/post.dart';
import '../../../models/post_types.dart';
import '../../../services/api_service.dart';
import '../../../services/feed_blocked_authors_store.dart';
import '../../../services/feed_cache_service.dart';
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
  Set<int>? _blockedAuthorIds;

  Future<Set<int>> _blockedAuthors() async {
    _blockedAuthorIds ??= await FeedBlockedAuthorsStore.load();
    return _blockedAuthorIds!;
  }

  List<Post> _withoutBlockedAuthors(List<Post> posts, Set<int> blocked) {
    if (blocked.isEmpty) return posts;
    return posts.where((p) => !blocked.contains(p.userId)).toList();
  }

  /// Больше не показывать посты этого автора в ленте (локально).
  Future<void> blockAuthor(int userId) async {
    final blocked = await _blockedAuthors();
    if (!blocked.add(userId)) return;
    _blockedAuthorIds = blocked;
    await FeedBlockedAuthorsStore.save(blocked);
    state = state.copyWith(
      posts: state.posts.where((p) => p.userId != userId).toList(),
    );
  }

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
      final blocked = await _blockedAuthors();
      final visible = _withoutBlockedAuthors(posts, blocked);

      state = state.copyWith(
        posts: visible.take(20).toList(),
        loading: false,
        hasMore: visible.length >= 20,
        // Курсор пагинации — id последнего поста страницы (совпадает с next_cursor бэкенда).
        lastPostId: visible.isNotEmpty ? visible.last.idString : null,
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
      final blocked = await _blockedAuthors();
      final uniqueNewPosts = newPosts
          .where((p) => !existingIds.contains(p.id))
          .toList();
      final visibleNew = _withoutBlockedAuthors(uniqueNewPosts, blocked);

      state = state.copyWith(
        posts: [...state.posts, ...visibleNew],
        loading: false,
        hasMore: newPosts.length >= 20,
        lastPostId: uniqueNewPosts.isNotEmpty
            ? uniqueNewPosts.last.idString
            : state.lastPostId,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: userVisibleError(e, fallback: 'Не удалось загрузить посты'),
      );
    }
  }

  /// Обновить один пост из API (лайки, счётчики).
  Future<void> refreshPost(String postId) async {
    final id = int.tryParse(postId);
    if (id == null) return;
    try {
      final pm = await ApiService.getPostById(id);
      if (pm == null) return;
      final updated = pm.toPost();
      final idx = state.posts.indexWhere((p) => p.id == id);
      if (idx < 0) return;
      final list = [...state.posts];
      list[idx] = updated;
      state = state.copyWith(posts: list);
      try {
        await FeedCacheService.instance.upsertPostModelInCache(pm);
      } catch (e) {
        if (kDebugMode) debugPrint('refreshPost cache: $e');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('refreshPost: $e\n$st');
      }
    }
  }

  /// Удалить пост из ленты (например, после скрытия)
  Future<void> removePost(String postId) async {
    final postIdInt = int.tryParse(postId);
    if (postIdInt == null) return;
    final updatedPosts = state.posts.where((p) => p.id != postIdInt).toList();
    state = state.copyWith(posts: updatedPosts);
    try {
      await FeedCacheService.instance.removePostFromCache(postId);
    } catch (e) {
      if (kDebugMode) debugPrint('removePost cache: $e');
    }
  }
}

