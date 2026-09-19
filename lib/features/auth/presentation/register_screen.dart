// Экран регистрации
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/auth_navigation.dart';
import '../../../../app/auth_route_paths.dart';
import '../../../../features/referral/pending_referral.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/pending_referral_store.dart';
import '../../../../services/push_notification_service.dart'
    deferred as push_svc;
import '../../../../utils/api_error_parser.dart';
import '../../../../widgets/app_gradient_background.dart';
import '../../../../widgets/server_connecting_hint.dart';
import '../../../../widgets/legal_consent_checkbox.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.initialReferralCode});

  final String? initialReferralCode;

  static const routeName = '/register';

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _invited = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _legalAccepted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateReferral());
  }

  Future<void> _hydrateReferral() async {
    final fromQuery = PendingReferral.extract(widget.initialReferralCode);
    if (fromQuery != null) {
      await PendingReferralStore.remember(fromQuery);
      if (!mounted) return;
      setState(() => _invited = true);
      return;
    }
    final stored = await PendingReferralStore.peek();
    if (!mounted || stored == null) return;
    setState(() => _invited = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_legalAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Примите политику конфиденциальности и пользовательское соглашение',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await AuthService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        acceptLegal: true,
        referralCode: PendingReferral.extract(widget.initialReferralCode) ??
            await PendingReferralStore.peek(),
      );

      unawaited(() async {
        try {
          await push_svc.loadLibrary();
          await push_svc.PushNotificationService.syncTokenAfterAuth();
        } catch (e) {
          debugPrint('FCM after register: $e');
        }
      }());

      if (mounted) {
        if (response.message != null && response.message!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message!)),
          );
        }
        if (!response.user.emailVerified) {
          navigateAfterAuth(
            context,
            AuthPaths.verifyEmailWithEmail(response.user.email),
          );
        } else {
          navigateAfterAuth(context, AuthPaths.feed);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AuthService.notifySessionReadyAfterLogin();
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось зарегистрироваться'),
            ),
            backgroundColor: scheme.error,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_handleRegister()),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e,
                  fallback: 'Не удалось зарегистрироваться. Попробуйте позже.'),
            ),
            backgroundColor: scheme.error,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_handleRegister()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация'),
      ),
      body: AppGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  // Имя
                  TextFormField(
                    textCapitalization: TextCapitalization.words,
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Имя',
                      hintText: 'Ваше имя',
                      prefixIcon: Icon(Icons.person_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите имя';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Почта',
                      hintText: 'name@mail.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите почту';
                      }
                      if (!value.contains('@')) {
                        return 'Введите корректный адрес почты';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Username (опционально)
                  TextFormField(
                    controller: _usernameController,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Имя пользователя',
                      hintText: '@username',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Пароль
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
                  const SizedBox(height: 16),
                  // Подтверждение пароля
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Подтвердите пароль',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscureConfirmPassword =
                              !_obscureConfirmPassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Подтвердите пароль';
                      }
                      if (value != _passwordController.text) {
                        return 'Пароли не совпадают';
                      }
                      return null;
                    },
                  ),
                  if (_invited) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Вас пригласили в HanWe — аккаунт привяжется к ссылке друга.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  LegalConsentCheckbox(
                    value: _legalAccepted,
                    onChanged: _isLoading
                        ? null
                        : (v) => setState(() => _legalAccepted = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Зарегистрироваться'),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(height: 12),
                    const ServerConnectingHint(),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Уже есть аккаунт? '),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go(AuthPaths.login),
                        child: const Text('Войти'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
