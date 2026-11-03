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
      base.endsWith('/register') ||
      base.endsWith('/signup') ||
      base.endsWith('/sign-up') ||
      base.endsWith('/registration') ||
      base.endsWith('/create-account') ||
      base.endsWith('/createaccount')) {
    return AuthPaths.register;
  }
  if (base.endsWith('/forgot-password') ||
      base.endsWith('/forgot') ||
      base.endsWith('/forgotpassword') ||
      base.endsWith('/forgot-pass') ||
      base.endsWith('/recoveraccount') ||
      base.endsWith('/recover-password')) {
    return _keepAuthQuery(AuthPaths.forgotPassword, target, hashUri);
  }
  if (base.endsWith('/reset-password') ||
      base.endsWith('/resetpassword') ||
      base.endsWith('/reset-pass') ||
      base.endsWith('/new-password') ||
      base.endsWith('/newpassword') ||
      base.endsWith('/password-reset') ||
      base.endsWith('/passwordreset')) {
    final token =
        target.queryParameters['token'] ?? hashUri?.queryParameters['token'];
    if ((token != null && token.isNotEmpty) ||
        base.endsWith('/reset-password')) {
      return _keepAuthQuery(AuthPaths.resetPassword, target, hashUri);
    }
    return _keepAuthQuery(AuthPaths.forgotPassword, target, hashUri);
  }
  if (base.endsWith('/confirm-email-change') ||
      base.endsWith('/confirmemailchange')) {
    return _keepAuthQuery(AuthPaths.confirmEmailChange, target, hashUri);
  }
  if (base.endsWith('/verify-email') ||
      base.endsWith('/verifyemail') ||
      base.endsWith('/email-code') ||
      base.endsWith('/emailcode') ||
      base.endsWith('/email-confirm') ||
      base.endsWith('/confirm-email')) {
    return _keepAuthQuery(AuthPaths.verifyEmail, target, hashUri);
  }
  if (base.endsWith('/2fa-verify') ||
      base.endsWith('/2fa') ||
      base.endsWith('/twofa') ||
      base.endsWith('/2step')) {
    return AuthPaths.twoFactorVerify;
  }
  if (base.endsWith('/otp') ||
      base.endsWith('/login-code') ||
      base.endsWith('/sms-code')) {
    return AuthPaths.login;
  }
  return AuthPaths.login;
}
