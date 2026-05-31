import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/community_video.dart';
import '../../../services/api_service.dart';
import '../../../utils/api_error_parser.dart';

enum SearchType {
  best, // Лучшее - поиск по всему
  author, // Автор - поиск только по авторам
  video, // Видео - поиск по названиям видео
  hashtag, // Хештеги - поиск по хештегам
  category, // Категории - поиск по категориям
}

class CommunitySearchState {
  const CommunitySearchState({
    required this.videos,
    required this.loading,
    required this.error,
    required this.searchQuery,
    required this.searchType,
    required this.filters,
  });

  factory CommunitySearchState.initial() => const CommunitySearchState(
        videos: [],
        loading: false,
        error: null,
        searchQuery: '',
        searchType: SearchType.best,
        filters: {},
      );

  final List<CommunityVideo> videos;
  final bool loading;
  final String? error;
  final String searchQuery;
  final SearchType searchType;
  final Map<String, dynamic> filters;

  CommunitySearchState copyWith({
    List<CommunityVideo>? videos,
    bool? loading,
    String? error,
    String? searchQuery,
    SearchType? searchType,
    Map<String, dynamic>? filters,
  }) {
    return CommunitySearchState(
      videos: videos ?? this.videos,
      loading: loading ?? this.loading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      searchType: searchType ?? this.searchType,
      filters: filters ?? this.filters,
    );
  }
}

final communitySearchControllerProvider =
    StateNotifierProvider<CommunitySearchController, CommunitySearchState>(
  (ref) => CommunitySearchController(),
);

class CommunitySearchController extends StateNotifier<CommunitySearchState> {
  CommunitySearchController() : super(CommunitySearchState.initial());

  Future<void> search(String query, {SearchType? type, Map<String, dynamic>? filters}) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(videos: [], loading: false, error: null);
      return;
    }

    state = state.copyWith(
      loading: true,
      error: null,
      searchQuery: query,
      searchType: type ?? state.searchType,
      filters: filters ?? state.filters,
    );

    try {
      String? serverTag = state.filters['tag'] as String?;
      if (serverTag == null || serverTag.isEmpty) {
        if (state.searchType == SearchType.hashtag) {
          var h = query.trim().toLowerCase();
          if (h.startsWith('#')) h = h.substring(1);
          serverTag = h.isEmpty ? null : h;
        }
      }
      final allVideos =
          await ApiService.fetchCommunityVideos(tag: serverTag);

      // Дополнительная фильтрация на клиенте по типу поиска
      List<CommunityVideo> filteredVideos = [];
      final queryLower = query.toLowerCase();

      switch (state.searchType) {
        case SearchType.author:
          filteredVideos = allVideos
              .where((video) => video.author.toLowerCase().contains(queryLower))
              .toList();
          break;
        case SearchType.video:
          filteredVideos = allVideos
              .where((video) => 
                  video.title.toLowerCase().contains(queryLower) ||
                  video.description.toLowerCase().contains(queryLower))
              .toList();
          break;
        case SearchType.hashtag:
          // Поиск по хештегам (тегам)
          final hashtag = queryLower.startsWith('#') 
              ? queryLower.substring(1) 
              : queryLower;
          filteredVideos = allVideos
              .where((video) =>
                  video.tags.any((tag) => 
                      tag.toLowerCase().contains(hashtag) ||
                      tag.toLowerCase() == hashtag))
              .toList();
          break;
        case SearchType.category:
          // Поиск по категориям (в тегах может быть категория)
          filteredVideos = allVideos
              .where((video) =>
                  video.tags.any((tag) => 
                      tag.toLowerCase() == queryLower ||
                      tag.toLowerCase().contains(queryLower)))
              .toList();
          break;
        case SearchType.best:
        default:
          filteredVideos = allVideos
              .where((video) =>
                  video.title.toLowerCase().contains(queryLower) ||
                  video.description.toLowerCase().contains(queryLower) ||
                  video.author.toLowerCase().contains(queryLower) ||
                  video.tags.any((tag) => tag.toLowerCase().contains(queryLower)))
              .toList();
          break;
      }

      // Применяем дополнительные фильтры
      if (state.filters.isNotEmpty) {
        if (state.filters.containsKey('tag') && state.filters['tag'] != null) {
          final tag = state.filters['tag'] as String;
          filteredVideos = filteredVideos
              .where((video) => video.tags.contains(tag))
              .toList();
        }
        if (state.filters.containsKey('minLikes') && state.filters['minLikes'] != null) {
          final minLikes = state.filters['minLikes'] as int;
          filteredVideos = filteredVideos
              .where((video) => video.likes >= minLikes)
              .toList();
        }
      }

      state = state.copyWith(
        videos: filteredVideos,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: userVisibleError(e, fallback: 'Не удалось выполнить поиск'),
      );
    }
  }

  void setSearchType(SearchType type) {
    if (state.searchQuery.isNotEmpty) {
      search(state.searchQuery, type: type);
    } else {
      state = state.copyWith(searchType: type);
    }
  }

  void setFilters(Map<String, dynamic> filters) {
    if (state.searchQuery.isNotEmpty) {
      search(state.searchQuery, filters: filters);
    } else {
      state = state.copyWith(filters: filters);
    }
  }

  void clearSearch() {
    state = CommunitySearchState.initial();
  }
}

