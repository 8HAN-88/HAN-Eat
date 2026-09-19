import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/auth_route_paths.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/otp_code_input.dart';
import '../../../widgets/server_connecting_hint.dart';
import '../otp_code.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.initialToken,
    this.initialEmail,
  });

  final String? initialToken;
  final String? initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _linkToken;
  bool _loading = false;
  bool _obscure = true;
  bool _codeError = false;

  String get _email => _emailController.text.trim();

  @override
  void initState() {
    super.initState();
    _emailController.text = (widget.initialEmail ?? '').trim();
    final token = (widget.initialToken ?? '').trim();
    if (isOtpCode(token)) {
      _codeController.text = normalizeOtpInput(token);
    } else if (isLegacyAuthToken(token)) {
      _linkToken = token;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final token = resolveAuthCode(
      typed: _codeController.text,
      linkToken: _linkToken,
    );
    if (!isAcceptableAuthCode(token)) {
      setState(() => _codeError = true);
      return;
    }
    if (isOtpCode(token) && _email.isEmpty) {
      setState(() => _codeError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите почту и код')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _codeError = false;
    });
    try {
      final result = await AuthService.resetPassword(
        token: token,
        newPassword: _passwordController.text,
        email: _email.isEmpty ? null : _email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        context.go(AuthPaths.login);
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _codeError = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось сменить пароль'),
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => unawaited(_submit()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_email.isEmpty || !_email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Укажите почту, чтобы получить новый код')),
      );
      throw AuthException('Укажите почту');
    }
    final result = await AuthService.forgotPassword(email: _email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Новый пароль')),
      body: AppGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Введите код из письма и новый пароль',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _linkToken != null
                        ? 'Ссылка из письма принята. Задайте новый пароль или введите свежий код.'
                        : 'Код из шести цифр. Действует 15 минут.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_loading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Почта',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Введите почту';
                      }
                      if (!v.contains('@')) return 'Некорректный адрес почты';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  OtpCodeInput(
                    controller: _codeController,
                    enabled: !_loading,
                    error: _codeError,
                    autofocus: _email.isNotEmpty,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: OtpResendControl(
                      enabled: !_loading,
                      startCooldown: (widget.initialEmail ?? '').isNotEmpty,
                      onResend: _resend,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Новый пароль',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 8) {
                        return 'Минимум 8 символов';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Повторите пароль',
                    ),
                    validator: (v) {
                      if (v != _passwordController.text) {
                        return 'Пароли не совпадают';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Сохранить пароль'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const ServerConnectingHint(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
