/// Контекст поиска — разделы приложения.
enum SearchScope {
  main,
  channels,
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
    case 'chats':
      return SearchScope.chats;
    // Legacy kitchen / old feed scopes → общий поиск ленты.
    case 'menu':
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
      // Legacy kitchen filter — treat as all posts.
      return null;
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
      case SearchScope.chats:
        return 'Имя, @username или название канала…';
    }
  }

  bool get usesChatsHubSearch => this == SearchScope.chats;
}
