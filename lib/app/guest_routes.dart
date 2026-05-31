/// Маршруты, доступные без авторизации (только вход и восстановление доступа).
bool routeAllowsGuestAccess(String location) {
  final loc = location.split('?').first;
  return loc == '/login' ||
      loc == '/register' ||
      loc == '/profile-auth' ||
      loc == '/forgot-password' ||
      loc == '/reset-password' ||
      loc.startsWith('/verify-email') ||
      loc.startsWith('/confirm-email-change');
}
