import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import 'auth_route_paths.dart';
import 'theme_mode_controller.dart';

/// Minimal web shell: login/register only.
///
/// Intentionally does **not** import [HanEatApp] / full [appRouterProvider], so
/// iPhone Safari can paint auth UI before downloading WebRTC/video/chat code.
class WebAuthApp extends ConsumerWidget {
  const WebAuthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = _authRouter;
    return MaterialApp.router(
      title: 'HAN Eat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

final GoRouter _authRouter = GoRouter(
  initialLocation: AuthPaths.login,
  routes: [
    GoRoute(
      path: AuthPaths.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AuthPaths.register,
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: AuthPaths.forgotPassword,
      builder: (context, state) {
        final email = state.uri.queryParameters['email'];
        return ForgotPasswordScreen(initialEmail: email);
      },
    ),
    GoRoute(
      path: AuthPaths.resetPassword,
      builder: (context, state) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: AuthPaths.verifyEmail,
      builder: (context, state) {
        final email = state.uri.queryParameters['email'] ?? '';
        return VerifyEmailScreen(email: email);
      },
    ),
  ],
);
