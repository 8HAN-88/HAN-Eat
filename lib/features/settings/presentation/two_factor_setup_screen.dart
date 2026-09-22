import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/totp_auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/otp_code_input.dart';
import '../../auth/otp_code.dart';

/// Enable or disable TOTP 2FA from Account Security.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _enabled = false;
  String? _error;
  TotpSetupInfo? _setup;
  String? _setupError;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _disableCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _disableCodeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled = await TotpAuthService.status();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _setup = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userVisibleError(e);
      });
    }
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _setupError = null;
    });
    try {
      final info = await TotpAuthService.setup();
      if (!mounted) return;
      setState(() {
        _setup = info;
        _setupError = null;
        _codeController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _setupError = userVisibleError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    final code = normalizeOtpInput(_codeController.text);
    if (!isOtpCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите 6-значный код')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await TotpAuthService.enable(code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Двухфакторная защита включена')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_enable()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final password = _passwordController.text;
    final code = normalizeOtpInput(_disableCodeController.text);
    if (password.isEmpty || !isOtpCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите пароль и код из приложения')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await TotpAuthService.disable(password: password, code: code);
      if (!mounted) return;
      _passwordController.clear();
      _disableCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Двухфакторная защита отключена')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e)),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () => unawaited(_disable()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Двухфакторная защита'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AccountSecurityRoute.path);
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(AccountSecurityRoute.path),
                          child: const Text('К безопасности'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _enabled ? Icons.verified_user : Icons.shield_outlined,
                        color: _enabled
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        _enabled ? 'Защита включена' : 'Защита выключена',
                      ),
                      subtitle: Text(
                        _enabled
                            ? 'При входе потребуется код из аутентификатора.'
                            : 'Добавьте Google Authenticator, Authy или аналог.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_enabled && _setup == null) ...[
                      FilledButton.icon(
                        onPressed: _busy ? null : _startSetup,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_moderator_outlined),
                        label: Text(_busy ? 'Настраиваем…' : 'Настроить'),
                      ),
                      if (_setupError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _setupError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _startSetup,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Повторить'),
                        ),
                      ],
                    ],
                    if (!_enabled && _setup != null) ...[
                      Text(
                        'Добавьте аккаунт вручную в приложении-аутентификаторе '
                        'и введите секретный ключ:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        _setup!.secret,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  letterSpacing: 1.2,
                                ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _setup!.secret),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ключ скопирован')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Скопировать ключ'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Код из приложения',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      OtpCodeInput(
                        controller: _codeController,
                        enabled: !_busy,
                        autofocus: false,
                        onCompleted: (_) => unawaited(_enable()),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _enable,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Включить защиту'),
                      ),
                    ],
                    if (_enabled) ...[
                      Text(
                        'Чтобы отключить, подтвердите паролем и кодом.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Пароль',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Код из приложения',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      OtpCodeInput(
                        controller: _disableCodeController,
                        enabled: !_busy,
                        autofocus: false,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _disable,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Отключить защиту'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
