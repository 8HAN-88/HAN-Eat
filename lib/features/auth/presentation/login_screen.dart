// Экран входа
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/app_router.dart';
import '../../../../app/app_bootstrap_state.dart';
import '../../../../core/app/app_variant.dart';
import '../../../../core/web/boot_ready_signal.dart';
import '../../../../core/web/hard_web_redirect.dart';
import '../../../../services/auth_service.dart';
import '../../../../utils/api_error_parser.dart';
import '../../../../services/push_notification_service.dart';
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

      unawaited(
        PushNotificationService.syncTokenAfterAuth().catchError(
          (Object e) => debugPrint('FCM after login: $e'),
        ),
      );

      if (!mounted) return;
      if (kIsWeb) {
        AuthService.notifySessionReadyAfterLogin();
        context.go(WebSessionLandingRoute.path);
        return;
      }
      // Let GoRouter redirect decide the destination to avoid navigation races
      // (manual context.go + auth redirect could produce white/error page).
      AuthService.notifySessionReadyAfterLogin();
      _postLoginFallbackTimer?.cancel();
      _postLoginFallbackTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        final userNow = AuthService.instance.currentUser;
        if (userNow == null) return;
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
        final homePath = kIsWeb
            ? WebSessionLandingRoute.path
            : (AppVariant.current.isKitchen ? MenuRoute.path : FeedRoute.path);
        // Web-only hard redirect if router got stuck on /login in some browsers.
        final redirected = hardNavigateToRoute(homePath);
        if (!redirected && mounted) {
          context.go(homePath);
        }
      });
      // Do not force extra navigation from login screen: redirects in GoRouter
      // are the single source of truth and race-free.
      setState(() => _isLoading = false);
    } on AuthException catch (e) {
      if (mounted) {
        if (e.isEmailNotVerified) {
          AuthService.notifySessionReadyAfterLogin();
          context.go(
            VerifyEmailRoute.withEmail(_emailController.text.trim()),
          );
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
                                ForgotPasswordRoute.withEmail(
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
                            : () => context.push(RegisterRoute.path),
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
                          color: Color(0xFF2AABEE),
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
