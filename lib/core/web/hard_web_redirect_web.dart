// ignore_for_file: avoid_web_libraries_in_flutter

/// Hard document navigations are disabled on web.
///
/// Safari/iOS often surfaces `location.replace` during boot/login as a white
/// screen + "server stopped responding". In-app routing must use GoRouter only.
bool hardNavigateToRoute(String routePath, {bool addRecoverQuery = false}) {
  assert(() {
    // ignore: avoid_print
    print(
      'HAN Eat: hardNavigateToRoute($routePath) ignored '
      '(addRecoverQuery=$addRecoverQuery)',
    );
    return true;
  }());
  return false;
}
