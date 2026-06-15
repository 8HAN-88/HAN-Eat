import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../utils/api_error_parser.dart';

/// Подтверждённый выход из аккаунта (единый UX).
Future<void> confirmAndSignOut(BuildContext context) async {
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _SignOutDialog(),
  );
  // Навигация выполняется внутри диалога до его закрытия — без повторного «мигания» экрана.
}

class _SignOutDialog extends StatefulWidget {
  const _SignOutDialog();

  @override
  State<_SignOutDialog> createState() => _SignOutDialogState();
}

class _SignOutDialogState extends State<_SignOutDialog> {
  bool _working = false;

  Future<void> _signOut() async {
    if (_working) return;
    if (!AuthService.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сервис авторизации не инициализирован'),
        ),
      );
      return;
    }

    setState(() => _working = true);
    try {
      await AuthService.instance.signOut();
      if (UserService.isInitialized) {
        UserService.instance.profile.value = null;
      }
      if (!mounted) return;
      final loc = GoRouterState.of(context).matchedLocation.split('?').first;
      if (loc != LoginRoute.path) {
        GoRouter.of(context).go(LoginRoute.path);
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userVisibleError(e, fallback: 'Не удалось выйти')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_working,
      child: AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: _working
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Выход из аккаунта...'),
                ],
              )
            : const Text('Вы уверены, что хотите выйти?'),
        actions: _working
            ? null
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: _signOut,
                  child: const Text('Выйти'),
                ),
              ],
      ),
    );
  }
}
