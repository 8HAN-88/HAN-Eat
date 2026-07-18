import 'hard_web_redirect_stub.dart'
    if (dart.library.html) 'hard_web_redirect_web.dart' as impl;

/// Performs a full-page navigation on web to recover from stuck router state.
/// Returns true when the redirect call has been issued.
bool hardNavigateToRoute(String routePath, {bool addRecoverQuery = false}) {
  return impl.hardNavigateToRoute(
    routePath,
    addRecoverQuery: addRecoverQuery,
  );
}
