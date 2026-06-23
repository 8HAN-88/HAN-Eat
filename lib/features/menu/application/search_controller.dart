import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/recipe.dart';
import '../../../services/api_service.dart';
import '../../../services/history_storage.dart';
import '../../../services/menu_search_cache.dart';
import '../../../utils/api_error_parser.dart';
import '../../settings/application/analysis_mode_controller.dart';

class SearchState {
  const SearchState({
    required this.recipes,
    required this.loading,
    required this.error,
    required this.hasSearched,
    this.recipeTranslationEnabled = false,
    this.recipeTranslationRequiresAi = false,
    this.recipeTranslationApiSupported = false,
    this.source,
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
  final bool recipeTranslationEnabled;
  final bool recipeTranslationRequiresAi;
  final bool recipeTranslationApiSupported;
  final String? source;

  /// Значение по умолчанию для [copyWith]: не менять поле [error].
  static const Object _errorUnset = Object();

  SearchState copyWith({
    List<Recipe>? recipes,
    bool? loading,
    Object? error = _errorUnset,
    bool? hasSearched,
    bool? recipeTranslationEnabled,
    bool? recipeTranslationRequiresAi,
    bool? recipeTranslationApiSupported,
    Object? source = _errorUnset,
  }) {
    return SearchState(
      recipes: recipes ?? this.recipes,
      loading: loading ?? this.loading,
      error: identical(error, _errorUnset) ? this.error : error as String?,
      hasSearched: hasSearched ?? this.hasSearched,
      recipeTranslationEnabled:
          recipeTranslationEnabled ?? this.recipeTranslationEnabled,
      recipeTranslationRequiresAi:
          recipeTranslationRequiresAi ?? this.recipeTranslationRequiresAi,
      recipeTranslationApiSupported:
          recipeTranslationApiSupported ?? this.recipeTranslationApiSupported,
      source: identical(source, _errorUnset) ? this.source : source as String?,
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
  int _requestId = 0;

  Future<void> search(
    String query, {
    Map<String, dynamic>? filters,
    List<String>? tags, // Теги категорий
    int? maxReadyTime, // Макс. время готовки в минутах
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final requestId = ++_requestId;
    final settings = _ref.read(analysisSettingsProvider);
    final cacheKey = MenuSearchCache.buildKey(
      query: trimmed,
      mode: settings.mode.name,
      language: settings.language,
      tags: tags?.join(','),
      maxReadyTime: maxReadyTime,
    );
    final cached = MenuSearchCache.peek(cacheKey);
    if (cached != null && cached.recipes.isNotEmpty) {
      state = state.copyWith(
        recipes: cached.recipes,
        loading: true,
        error: null,
        hasSearched: true,
        recipeTranslationEnabled: cached.recipeTranslationEnabled,
        recipeTranslationRequiresAi: cached.recipeTranslationRequiresAi,
        recipeTranslationApiSupported: cached.recipeTranslationApiSupported,
        source: cached.source,
      );
    } else {
      state = state.copyWith(loading: true, error: null);
    }
    try {
      final result = await ApiService.searchRecipesResult(
        trimmed,
        mode: settings.mode,
        language: settings.language,
        filters: filters,
        tags: tags,
        maxReadyTime: maxReadyTime,
      );
      if (requestId != _requestId) return;
      unawaited(MenuSearchCache.save(cacheKey, result));
      state = state.copyWith(
        recipes: result.recipes,
        loading: false,
        error: null,
        hasSearched: true,
        recipeTranslationEnabled: result.recipeTranslationEnabled,
        recipeTranslationRequiresAi: result.recipeTranslationRequiresAi,
        recipeTranslationApiSupported: result.recipeTranslationApiSupported,
        source: result.source,
      );
      await HistoryStorage.addQuery(trimmed, settings.mode);
    } catch (e) {
      if (requestId != _requestId) return;
      if (cached != null && cached.recipes.isNotEmpty) {
        state = state.copyWith(
          recipes: cached.recipes,
          loading: false,
          error: null,
          hasSearched: true,
          recipeTranslationEnabled: cached.recipeTranslationEnabled,
          recipeTranslationRequiresAi: cached.recipeTranslationRequiresAi,
          recipeTranslationApiSupported: cached.recipeTranslationApiSupported,
          source: cached.source,
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        error: userVisibleError(e, fallback: 'Не удалось выполнить поиск'),
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
    _requestId++;
    state = SearchState.initial();
  }

  /// Быстрый поиск по тегу (например «Быстро», тег quick-and-easy).
  Future<void> searchByTag(String query, String tag,
      {int? maxReadyTime}) async {
    final requestId = ++_requestId;
    final settings = _ref.read(analysisSettingsProvider);
    final effectiveQuery = query.trim().isEmpty ? tag : query.trim();
    final cacheKey = MenuSearchCache.buildKey(
      query: effectiveQuery,
      mode: settings.mode.name,
      language: settings.language,
      tags: tag,
      maxReadyTime: maxReadyTime,
    );
    final cached = MenuSearchCache.peek(cacheKey);
    if (cached != null && cached.recipes.isNotEmpty) {
      state = state.copyWith(
        recipes: cached.recipes,
        loading: true,
        error: null,
        hasSearched: true,
        recipeTranslationEnabled: cached.recipeTranslationEnabled,
        recipeTranslationRequiresAi: cached.recipeTranslationRequiresAi,
        recipeTranslationApiSupported: cached.recipeTranslationApiSupported,
        source: cached.source,
      );
    } else {
      state = state.copyWith(loading: true, error: null);
    }
    try {
      final result = await ApiService.searchRecipesResult(
        effectiveQuery,
        mode: settings.mode,
        language: settings.language,
        tags: [tag],
        maxReadyTime: maxReadyTime,
      );
      if (requestId != _requestId) return;
      unawaited(MenuSearchCache.save(cacheKey, result));
      state = state.copyWith(
        recipes: result.recipes,
        loading: false,
        error: null,
        hasSearched: true,
        recipeTranslationEnabled: result.recipeTranslationEnabled,
        recipeTranslationRequiresAi: result.recipeTranslationRequiresAi,
        recipeTranslationApiSupported: result.recipeTranslationApiSupported,
        source: result.source,
      );
      await HistoryStorage.addQuery(effectiveQuery, settings.mode);
    } catch (e) {
      if (requestId != _requestId) return;
      if (cached != null && cached.recipes.isNotEmpty) {
        state = state.copyWith(
          recipes: cached.recipes,
          loading: false,
          error: null,
          hasSearched: true,
          recipeTranslationEnabled: cached.recipeTranslationEnabled,
          recipeTranslationRequiresAi: cached.recipeTranslationRequiresAi,
          recipeTranslationApiSupported: cached.recipeTranslationApiSupported,
          source: cached.source,
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        error: userVisibleError(e, fallback: 'Не удалось выполнить поиск'),
        hasSearched: true,
      );
    }
  }

  bool get hasResults => state.recipes.isNotEmpty;
}
