import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../services/auth_service.dart';
import '../../../utils/api_error_parser.dart';
import '../../../widgets/app_empty_state.dart';

class ConfirmEmailChangeScreen extends StatefulWidget {
  const ConfirmEmailChangeScreen({super.key, required this.token});

  final String token;

  @override
  State<ConfirmEmailChangeScreen> createState() =>
      _ConfirmEmailChangeScreenState();
}

class _ConfirmEmailChangeScreenState extends State<ConfirmEmailChangeScreen> {
  bool _loading = true;
  bool _success = false;
  String? _message;

  bool get _tokenInvalid =>
      widget.token.trim().length < 16;

  @override
  void initState() {
    super.initState();
    if (_tokenInvalid) {
      _loading = false;
      _message = 'Ссылка недействительна или устарела';
      return;
    }
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _message = null;
      _success = false;
    });
    try {
      final result = await AuthService.confirmEmailChange(token: widget.token);
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = userVisibleError(
          e,
          fallback: 'Не удалось подтвердить смену email',
        );
        _success = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Смена email')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tokenInvalid) {
      return AppEmptyState(
        icon: Icons.link_off_rounded,
        title: 'Неверная ссылка',
        subtitle: _message,
        action: FilledButton(
          onPressed: () => context.go(LoginRoute.path),
          child: const Text('На экран входа'),
        ),
      );
    }

    if (_success) {
      return AppEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'Email обновлён',
        subtitle: _message ?? 'Войдите с новым адресом',
        action: FilledButton(
          onPressed: () => context.go(LoginRoute.path),
          child: const Text('Войти'),
        ),
      );
    }

    return AppEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Не удалось подтвердить',
      subtitle: _message,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: _run,
            child: const Text('Повторить'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(LoginRoute.path),
            child: const Text('На экран входа'),
          ),
        ],
      ),
    );
  }
}
