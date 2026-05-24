import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';

class ConfirmEmailChangeScreen extends StatefulWidget {
  const ConfirmEmailChangeScreen({super.key, required this.token});

  final String token;

  @override
  State<ConfirmEmailChangeScreen> createState() =>
      _ConfirmEmailChangeScreenState();
}

class _ConfirmEmailChangeScreenState extends State<ConfirmEmailChangeScreen> {
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await AuthService.confirmEmailChange(token: widget.token);
      final user = await AuthService.getCurrentUser();
      if (user != null) {
        await AuthService.logout();
      }
      if (mounted) {
        setState(() {
          _message = result.message;
          _loading = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Смена email')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_message ?? '', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go(LoginRoute.path),
                      child: const Text('Войти'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
