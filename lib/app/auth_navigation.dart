import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_bootstrap_state.dart';
import 'auth_route_paths.dart';

/// Post-auth navigation that keeps the web cold-start bundle light.
///
/// On [kIsWeb], destinations outside the auth shell trigger deferred load of
/// the full app instead of importing [app_router] into the first JS chunk.
void navigateAfterAuth(BuildContext context, String destination) {
  if (kIsWeb && !AppBootstrapState.loadFullApp.value) {
    final staysInAuthShell = destination == AuthPaths.login ||
        destination == AuthPaths.register ||
        destination == AuthPaths.forgotPassword ||
        destination == AuthPaths.resetPassword ||
        destination.startsWith(AuthPaths.verifyEmail);
    if (staysInAuthShell) {
      context.go(destination);
      return;
    }
    AppBootstrapState.enterFullApp();
    return;
  }
  context.go(destination);
}
