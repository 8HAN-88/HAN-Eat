/// Контекст поиска — разделы приложения.
enum SearchScope {
  main,
  channels,
  menu,
  /// Чаты: люди и каталог каналов (кнопка поиска в разделе «Чаты»).
  chats,
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
    case 'chats':
      return SearchScope.chats;
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
        return 'Поиск';
      case SearchScope.chats:
        return 'Поиск';
    }
  }

  String get hint {
    switch (this) {
      case SearchScope.main:
        return 'Посты, люди, рилсы…';
      case SearchScope.channels:
        return 'Название или описание канала…';
      case SearchScope.menu:
        return 'Посты, люди, рилсы…';
      case SearchScope.chats:
        return 'Имя, @username или название канала…';
    }
  }

  bool get usesRecipeSearch => false;

  bool get usesChatsHubSearch => this == SearchScope.chats;
}
