import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/auth_route_paths.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';
import '../../../widgets/app_gradient_background.dart';
import '../../../widgets/otp_code_input.dart';
import '../otp_code.dart';

class ConfirmEmailChangeScreen extends StatefulWidget {
  const ConfirmEmailChangeScreen({
    super.key,
    this.token = '',
    this.email,
  });

  final String token;
  final String? email;

  @override
  State<ConfirmEmailChangeScreen> createState() =>
      _ConfirmEmailChangeScreenState();
}

class _ConfirmEmailChangeScreenState extends State<ConfirmEmailChangeScreen> {
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  String? _linkToken;
  bool _loading = false;
  bool _success = false;
  bool _codeError = false;
  String? _message;

  String get _email => _emailController.text.trim().isNotEmpty
      ? _emailController.text.trim()
      : (widget.email ?? '').trim();

  @override
  void initState() {
    super.initState();
    _emailController.text = (widget.email ?? '').trim();
    final token = widget.token.trim();
    if (isOtpCode(token)) {
      _codeController.text = normalizeOtpInput(token);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_run(token));
      });
    } else if (isLegacyAuthToken(token)) {
      _linkToken = token;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_run(token));
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _run(String raw) async {
    final token = resolveAuthCode(typed: raw, linkToken: _linkToken);
    if (!isAcceptableAuthCode(token)) {
      setState(() => _codeError = true);
      return;
    }
    if (isOtpCode(token) && _email.isEmpty) {
      setState(() {
        _codeError = true;
        _message = 'Укажите новую почту и код';
      });
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
      _success = false;
      _codeError = false;
    });
    try {
      final result = await AuthService.confirmEmailChange(
        token: token,
        email: _email.isEmpty ? null : _email,
      );
      final user = await AuthService.getCurrentUser();
      if (user != null) {
        await AuthService.logout();
      }
      if (!mounted) return;
      setState(() {
        _message = result.message;
        _success = true;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _success = false;
        _loading = false;
        _codeError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = userVisibleError(
          e,
          fallback: 'Не удалось подтвердить смену почты',
        );
        _success = false;
        _loading = false;
        _codeError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Смена почты')),
      body: AppGradientBackground(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_success) {
      return AppEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'Почта обновлена',
        subtitle: _message ?? 'Войдите с новым адресом',
        action: FilledButton(
          onPressed: () => context.go(AuthPaths.login),
          child: const Text('Войти'),
        ),
      );
    }

    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Введите код с новой почты',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Шестизначный код — в письме на новый адрес.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Новая почта',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            OtpCodeInput(
              controller: _codeController,
              enabled: !_loading,
              error: _codeError,
              onCompleted: (code) => unawaited(_run(code)),
            ),
            if (_message != null && !_success) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed:
                  _loading ? null : () => unawaited(_run(_codeController.text)),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Подтвердить'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go(AuthPaths.login),
              child: const Text('На экран входа'),
            ),
          ],
        ),
      ),
    );
  }
}
