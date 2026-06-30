import '../../../app/app_router.dart';
import '../../../core/app/app_variant.dart';
import '../../search/application/search_scope.dart';

/// Маршрут поиска по активному разделу нижней панели.
String? contextualSearchPath(int shellIndex) {
  if (AppVariant.current.isKitchen) {
    switch (shellIndex) {
      case 0:
        return SearchRoute.pathFor(scope: SearchScope.menu);
      case 3:
        return null;
      default:
        return SearchRoute.pathFor(scope: SearchScope.main);
    }
  }

  switch (shellIndex) {
    case 3:
      return null;
    case 1:
      return SearchRoute.pathFor(scope: SearchScope.chats);
    case 2:
      return SearchRoute.pathFor(scope: SearchScope.menu);
    case 0:
    default:
      return SearchRoute.pathFor(scope: SearchScope.main);
  }
}
