import '../features/referral/pending_referral.dart';
import 'auth_route_paths.dart';
import 'web_app_path.dart';

String _keepAuthQuery(String path, Uri uri, [Uri? hashUri]) {
  final email = uri.queryParameters['email'] ?? hashUri?.queryParameters['email'];
  final token = uri.queryParameters['token'] ?? hashUri?.queryParameters['token'];
  if ((email == null || email.isEmpty) && (token == null || token.isEmpty)) {
    return path;
  }
  return Uri(
    path: path,
    queryParameters: {
      if (token != null && token.isNotEmpty) 'token': token,
      if (email != null && email.isNotEmpty) 'email': email,
    },
  ).toString();
}

/// Лёгкий web-шелл: инвайт, вход и письма с кодом — без полного приложения.
String webAuthInitialLocation([Uri? uri]) {
  final target = uri ?? Uri.base;
  final ref = PendingReferral.queryRef(target);
  if (ref != null) {
    return AuthPaths.registerWithRef(ref);
  }

  final hashUri = target.fragment.trim().isEmpty
      ? null
      : Uri.tryParse(
          target.fragment.startsWith('/')
              ? 'https://haneat.app${target.fragment}'
              : 'https://haneat.app/${target.fragment}',
        );
  var path = hashFragmentToGoPath(target.fragment);
  path ??= browserPathToGoPath(target.path);
  final base = (path ?? target.path).split('?').first.toLowerCase();

  if (base.endsWith('/invite') ||
      base.contains('/invite/') ||
      base.endsWith('/register')) {
    return AuthPaths.register;
  }
  if (base.endsWith('/forgot-password')) {
    return _keepAuthQuery(AuthPaths.forgotPassword, target, hashUri);
  }
  if (base.endsWith('/reset-password')) {
    return _keepAuthQuery(AuthPaths.resetPassword, target, hashUri);
  }
  if (base.endsWith('/verify-email')) {
    return _keepAuthQuery(AuthPaths.verifyEmail, target, hashUri);
  }
  if (base.endsWith('/confirm-email-change')) {
    return _keepAuthQuery(AuthPaths.confirmEmailChange, target, hashUri);
  }
  if (base.endsWith('/2fa-verify')) {
    return AuthPaths.twoFactorVerify;
  }
  return AuthPaths.login;
}
