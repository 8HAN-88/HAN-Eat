import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email, this.initialToken});

  final String? email;
  final String? initialToken;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _tokenController = TextEditingController();
  bool _loading = false;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.isNotEmpty) {
      _tokenController.text = widget.initialToken!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyWithToken());
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _verifyWithToken() async {
    final token = _tokenController.text.trim();
    if (token.length < 16) return;
    setState(() => _loading = true);
    try {
      final result = await AuthService.verifyEmail(token: token);
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
        context.go(FeedRoute.path);
      } else {
        context.go(LoginRoute.path);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleError(e, fallback: 'Не удалось подтвердить email'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      final result = await AuthService.resendVerification(
        email: widget.email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _verified ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _verified
                    ? 'Email подтверждён'
                    : 'Мы отправили письмо${email.isNotEmpty ? ' на $email' : ''}. '
                        'Откройте ссылку в письме или вставьте код ниже.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Код из письма',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _verifyWithToken,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Подтвердить'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _loading ? null : _resend,
                child: const Text('Отправить письмо ещё раз'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go(LoginRoute.path),
                child: const Text('Ко входу'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
