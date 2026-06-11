/// Контекст поиска — три основных раздела приложения.
enum SearchScope {
  main,
  channels,
  menu,
}

SearchScope? searchScopeFromQuery(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  switch (raw) {
    case 'main':
      return SearchScope.main;
    case 'channels':
      return SearchScope.channels;
    case 'menu':
      return SearchScope.menu;
    // Старые значения из предыдущей версии → общий поиск ленты.
    case 'subscriptions':
    case 'recommendations':
    case 'reels':
    case 'profile':
      return SearchScope.main;
    default:
      return null;
  }
}

String? feedFilterToPostType(String? feedType) {
  switch (feedType) {
    case 'photos':
      return 'photo';
    case 'recipes':
      return 'recipe';
    case 'reels':
      return 'reel';
    default:
      return null;
  }
}

extension SearchScopeLabels on SearchScope {
  String get title {
    switch (this) {
      case SearchScope.main:
        return 'Поиск';
      case SearchScope.channels:
        return 'Поиск каналов';
      case SearchScope.menu:
        return 'Поиск рецептов';
    }
  }

  String get hint {
    switch (this) {
      case SearchScope.main:
        return 'Посты, рилсы, рецепты в ленте…';
      case SearchScope.channels:
        return 'Название или описание канала…';
      case SearchScope.menu:
        return 'Название, ингредиенты, теги…';
    }
  }

  bool get usesRecipeSearch => this == SearchScope.menu;
}
