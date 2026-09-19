import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/auth_navigation.dart';
import '../../../app/auth_route_paths.dart';
import '../../../features/referral/pending_referral_binder.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/otp_code_input.dart';
import '../otp_code.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email, this.initialToken});

  final String? email;
  final String? initialToken;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _verified = false;
  bool _codeError = false;

  String get _email => _emailController.text.trim().isNotEmpty
      ? _emailController.text.trim()
      : (widget.email ?? '').trim();

  @override
  void initState() {
    super.initState();
    unawaited(PendingReferralBinder.applyIfNeeded());
    _emailController.text = (widget.email ?? '').trim();
    final token = (widget.initialToken ?? '').trim();
    if (isAcceptableAuthCode(token)) {
      _codeController.text =
          isOtpCode(token) ? normalizeOtpInput(token) : token;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_verifyWithToken(token));
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _verifyWithToken(String raw) async {
    final token = normalizeOtpInput(raw);
    if (!isAcceptableAuthCode(token)) return;
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
      final result = await AuthService.verifyEmail(
        token: token,
        email: _email.isEmpty ? null : _email,
      );
      if (!mounted) return;
      setState(() => _verified = true);
      final user = await AuthService.getCurrentUser();
      if (user != null) {
        await AuthService.persistUpdatedUser(
          user.copyWith(emailVerified: true),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      final stillAuth = await AuthService.isAuthenticated();
      if (!mounted) return;
      if (stillAuth) {
        unawaited(PendingReferralBinder.applyIfNeeded());
        navigateAfterAuth(context, AuthPaths.feed);
      } else {
        context.go(AuthPaths.login);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _codeError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Неверный код. Попробуйте снова'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_verifyWithToken(token)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _codeError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userVisibleError(e, fallback: 'Не удалось подтвердить почту'),
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_verifyWithToken(token)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      final result = await AuthService.resendVerification(
        email: _email.isEmpty ? widget.email : _email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось отправить письмо'),
            ),
          ),
        );
      }
      rethrow;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось отправить письмо'),
            ),
          ),
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _returnToLogin() async {
    await AuthService.instance.signOut(notifySession: false);
    if (!mounted) return;
    context.go(AuthPaths.login);
    AuthService.instance.notifySessionCleared();
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение почты')),
      body: AppGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _verified
                      ? Icons.mark_email_read_outlined
                      : Icons.password_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _verified ? 'Почта подтверждена' : 'Введите код из письма',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (!_verified)
                  Text(
                    email.isNotEmpty
                        ? 'Шестизначный код отправили на $email'
                        : 'Шестизначный код — в письме HanWe',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (!_verified && (widget.email ?? '').trim().isEmpty) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    enabled: !_loading,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Почта',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (!_verified) ...[
                  const SizedBox(height: 24),
                  OtpCodeInput(
                    controller: _codeController,
                    enabled: !_loading,
                    error: _codeError,
                    onCompleted: (code) => unawaited(_verifyWithToken(code)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading
                        ? null
                        : () => unawaited(
                              _verifyWithToken(_codeController.text),
                            ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Подтвердить'),
                  ),
                  const SizedBox(height: 4),
                  OtpResendControl(
                    enabled: !_loading,
                    onResend: _resend,
                  ),
                  Text(
                    'Не видите письмо? Проверьте «Спам» / «Нежелательная почта».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _returnToLogin,
                  child: const Text('Ко входу'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
