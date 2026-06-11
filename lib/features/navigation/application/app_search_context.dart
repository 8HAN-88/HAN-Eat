import '../../../app/app_router.dart';
import '../../search/application/search_scope.dart';

/// Маршрут поиска по активному разделу нижней панели.
///
/// Контексты: главная, меню. Чаты — inline-поиск на [ChatsHubScreen].
/// Профиль (index 3) — без поиска.
String? contextualSearchPath(int shellIndex) {
  switch (shellIndex) {
    case 1:
    case 3:
      return null;
    case 2:
      return SearchRoute.pathFor(scope: SearchScope.menu);
    case 0:
    default:
      return SearchRoute.pathFor(scope: SearchScope.main);
  }
}

bool usesChatsHubInlineSearch(int shellIndex) => shellIndex == 1;
