import '../../../app/app_router.dart';
import '../../search/application/search_scope.dart';

/// Маршрут поиска по активному разделу нижней панели.
String? contextualSearchPath(int shellIndex) {
  switch (shellIndex) {
    case 3:
      return null;
    case 1:
      return SearchRoute.pathFor(scope: SearchScope.chats);
    case 2:
      return SearchRoute.pathFor(scope: SearchScope.main);
    case 0:
    default:
      return SearchRoute.pathFor(scope: SearchScope.main);
  }
}
