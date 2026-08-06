import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/auth_navigation.dart';
import '../../../app/auth_route_paths.dart';
import '../../../services/auth_service.dart';
import '../../../services/push_notification_service.dart' deferred as push_svc;
import '../../../utils/api_error_parser.dart';

/// Enter TOTP code after password/OAuth when server requires 2FA.
class TwoFactorVerifyScreen extends StatefulWidget {
  const TwoFactorVerifyScreen({
    super.key,
    required this.pendingToken,
    this.email,
  });

  final String pendingToken;
  final String? email;

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  Timer? _postLoginFallbackTimer;

  @override
  void dispose() {
    _postLoginFallbackTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.verifyTwoFactorLogin(
        pendingToken: widget.pendingToken,
        code: _codeController.text,
      );
      unawaited(() async {
        try {
          await push_svc.loadLibrary();
          await push_svc.PushNotificationService.syncTokenAfterAuth();
        } catch (e) {
          debugPrint('FCM after 2FA login: $e');
        }
      }());
      if (!mounted) return;
      final user = AuthService.instance.currentUser;
      final destination = (user != null && user.legalConsentRequired)
          ? AuthPaths.legalConsent
          : AuthPaths.feed;
      navigateAfterAuth(context, destination);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AuthService.notifySessionReadyAfterLogin();
      });
      _postLoginFallbackTimer?.cancel();
      _postLoginFallbackTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (AuthService.instance.currentUser == null) return;
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
        navigateAfterAuth(context, destination);
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userVisibleError(e))),
      );
    } finally {
      if (mounted && AuthService.instance.currentUser == null) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailHint = (widget.email ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Код подтверждения'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => context.go(AuthPaths.login),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Введите 6-значный код из приложения-аутентификатора'
                  '${emailHint.isEmpty ? '' : ' для $emailHint'}.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  enabled: !_loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Код',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 6) {
                      return 'Введите 6 цифр';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Подтвердить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
