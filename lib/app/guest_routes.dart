/// Маршруты, доступные без входа (просмотр ленты, каналов, рецептов).
bool routeAllowsGuestAccess(String location) {
  final loc = location.split('?').first;
  if (loc == '/login' ||
      loc == '/register' ||
      loc == '/profile-auth' ||
      loc == '/forgot-password' ||
      loc == '/reset-password' ||
      loc.startsWith('/verify-email') ||
      loc.startsWith('/confirm-email-change')) {
    return true;
  }
  if (loc == '/' ||
      loc == '/feed' ||
      loc == '/channels' ||
      loc == '/support-security') {
    return true;
  }
  if (loc.startsWith('/channel/') || loc.startsWith('/recipe/')) {
    return true;
  }
  return false;
}
