import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/recipe.dart';
import '../../../services/api_service.dart';
import '../../../services/history_storage.dart';
import '../../settings/application/analysis_mode_controller.dart';

class SearchState {
  const SearchState({
    required this.recipes,
    required this.loading,
    required this.error,
    required this.hasSearched,
  });

  factory SearchState.initial() => const SearchState(
        recipes: [],
        loading: false,
        error: null,
        hasSearched: false,
      );

  final List<Recipe> recipes;
  final bool loading;
  final String? error;
  final bool hasSearched;

  SearchState copyWith({
    List<Recipe>? recipes,
    bool? loading,
    String? error,
    bool? hasSearched,
  }) {
    return SearchState(
      recipes: recipes ?? this.recipes,
      loading: loading ?? this.loading,
      error: error,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

final searchControllerProvider =
    StateNotifierProvider<SearchController, SearchState>(
  (ref) => SearchController(ref),
);

class SearchController extends StateNotifier<SearchState> {
  SearchController(this._ref) : super(SearchState.initial());

  final Ref _ref;

  Future<void> search(
    String query, {
    Map<String, dynamic>? filters,
    List<String>? tags, // Теги категорий
    int? maxReadyTime, // Макс. время готовки в минутах
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final settings = _ref.read(analysisSettingsProvider);

    state = state.copyWith(loading: true, error: null);
    try {
      final recipes = await ApiService.searchRecipes(
        trimmed,
        mode: settings.mode,
        language: settings.language,
        filters: filters,
        tags: tags,
        maxReadyTime: maxReadyTime,
      );
      state = state.copyWith(
        recipes: recipes,
        loading: false,
        hasSearched: true,
      );
      await HistoryStorage.addQuery(trimmed, settings.mode);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Ошибка поиска: $e',
        hasSearched: true,
      );
    }
  }

  void resetError() {
    if (state.error != null) {
      state = state.copyWith(error: null);
    }
  }

  void reset() {
    state = SearchState.initial();
  }

  /// Быстрый поиск по тегу (например «Быстро», тег quick-and-easy).
  Future<void> searchByTag(String query, String tag, {int? maxReadyTime}) async {
    final settings = _ref.read(analysisSettingsProvider);
    state = state.copyWith(loading: true, error: null);
    try {
      final recipes = await ApiService.searchRecipes(
        query.trim().isEmpty ? tag : query,
        mode: settings.mode,
        language: settings.language,
        tags: [tag],
        maxReadyTime: maxReadyTime,
      );
      state = state.copyWith(
        recipes: recipes,
        loading: false,
        hasSearched: true,
      );
      await HistoryStorage.addQuery(query.trim().isEmpty ? tag : query, settings.mode);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Ошибка поиска: $e',
        hasSearched: true,
      );
    }
  }

  bool get hasResults => state.recipes.isNotEmpty;
}

