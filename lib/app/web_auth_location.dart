import '../features/referral/pending_referral.dart';
import 'auth_route_paths.dart';

/// Лёгкий web-шелл должен сразу открыть регистрацию, если в URL есть инвайт.
String webAuthInitialLocation([Uri? uri]) {
  final target = uri ?? Uri.base;
  final ref = PendingReferral.queryRef(target);
  if (ref != null) {
    return AuthPaths.registerWithRef(ref);
  }
  final path = target.path.toLowerCase();
  if (path.contains('/invite') || path.contains('/register')) {
    return AuthPaths.register;
  }
  return AuthPaths.login;
}
