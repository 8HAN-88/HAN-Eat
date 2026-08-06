// Экран входа
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/app_bootstrap_state.dart';
import '../../../../app/auth_navigation.dart';
import '../../../../app/auth_route_paths.dart';
import '../../../../core/theme/color_schemes.dart';
import '../../../../core/web/boot_ready_signal.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/push_notification_service.dart' deferred as push_svc;
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_brand_logo.dart';
import '../../../../widgets/app_gradient_background.dart';
import '../../../../widgets/pwa_install_banner.dart';
import '../../../../widgets/server_connecting_hint.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  Timer? _postLoginFallbackTimer;

  @override
  void initState() {
    super.initState();
    AppBootstrapState.primaryUiReady.value = true;
    notifyPrimaryUiReady();
  }

  @override
  void dispose() {
    _postLoginFallbackTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final auth = await AuthService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      unawaited(() async {
        try {
          await push_svc.loadLibrary();
          await push_svc.PushNotificationService.syncTokenAfterAuth();
        } catch (e) {
          debugPrint('FCM after login: $e');
        }
      }());

      if (!mounted) return;

      // CRITICAL: navigate FIRST, then notify session. Bumping sessionRevision
      // before context.go races GoRouter's /login→/feed redirect with an
      // explicit go into StatefulShellRoute and leaves an empty shell that
      // CanvasKit paints as a white screen (same pattern as sign-out helper).
      // On web, destinations outside the auth shell load the deferred full app.
      final String destination;
      if (!auth.user.emailVerified) {
        destination =
            AuthPaths.verifyEmailWithEmail(_emailController.text.trim());
      } else if (auth.user.legalConsentRequired) {
        destination = AuthPaths.legalConsent;
      } else {
        destination =
            AuthPaths.feed;
      }
      navigateAfterAuth(context, destination);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AuthService.notifySessionReadyAfterLogin();
      });

      _postLoginFallbackTimer?.cancel();
      _postLoginFallbackTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        final userNow = AuthService.instance.currentUser;
        if (userNow == null) return;
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
        navigateAfterAuth(context, destination);
      });
      setState(() => _isLoading = false);
    } on AuthException catch (e) {
      if (mounted) {
        if (e.isEmailNotVerified) {
          navigateAfterAuth(
            context,
            AuthPaths.verifyEmailWithEmail(_emailController.text.trim()),
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AuthService.notifySessionReadyAfterLogin();
          });
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e,
                  fallback: 'Не удалось войти. Проверьте email и пароль.'),
            ),
          ),
        );
      }
    } finally {
      // Keep the dark "Входим…" overlay until route changes on success.
      if (mounted && AuthService.instance.currentUser == null) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0F1319),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text('Вход'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppGradientBackground(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 56),
                        const Center(
                          child: AppBrandLogo(
                            layout: AppBrandLogoLayout.horizontal,
                            width: 200,
                          ),
                        ),
                        const SizedBox(height: 40),
                  // Email поле
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'example@mail.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите email';
                      }
                      if (!value.contains('@')) {
                        return 'Введите корректный email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Пароль поле
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      hintText: 'Минимум 8 символов',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите пароль';
                      }
                      if (value.length < 8) {
                        return 'Пароль должен быть минимум 8 символов';
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push(
                                AuthPaths.forgotPasswordWithEmail(
                                  _emailController.text.trim(),
                                ),
                              ),
                      child: const Text('Забыли пароль?'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(height: 12),
                    const ServerConnectingHint(),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Нет аккаунта? '),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.push(AuthPaths.register),
                        child: const Text('Зарегистрироваться'),
                      ),
                    ],
                  ),
                        const SizedBox(height: 8),
                        const PwaInstallBanner(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const ColoredBox(
                color: Color(0xE60F1319),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Входим…',
                        style: TextStyle(
                          color: Color(0xFFF7F8FA),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
